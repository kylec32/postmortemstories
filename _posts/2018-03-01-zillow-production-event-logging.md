---
layout: post
title: "Zillow: Debugging Production with Event Logging"
description: "Explanation of how the engineers at Zillow debugged a production searching issue."
tags: [zillow, data, elasticsearch, Ruby, search]
comments: false
author: Zachary Wright
author_link: https://www.zillow.com/engineering/author/zachwr/
---

_[Originally Posted On the Zillow Engineering Blog](https://www.zillow.com/engineering/debugging-production-event-logging/)_

# The Bug
A while back our team received a bug report that any developer of an application with search functionality dreads to see: the contents of our search results occasionally included items that didn't match the given criteria.

As you can imagine, this bug quickly climbed the priority ladder. For a site built upon the foundation of searching for apartments, we need to be sure the results we return fit the query parameters given.

An initial round of debugging revealed the reason for the issue, but not the cause: the data in our [ElasticSearch](https://www.elastic.co/) index did not always match the data in our SQL database.

ElasticSearch is a search engine. You store data in it, just like a database, but it is schema-less and has incredibly powerful and performant search capabilities. Our infrastructure is set up so that when a record, such as an apartment, is saved to our SQL database, it automatically stores the attributes that we want to be able to search on into a corresponding apartment index in ElasticSearch.

This process is called "indexing," and it happens every time a record is created or updated. When a renter searches for apartments with less than $2,000 rent, this search is ran with ElasticSearch, then the returned apartment id's are used to fetch the actual records from the SQL database, which are then returned to the user to view in their browser.

Somehow these two data sources were diverging. The rent for an apartment might be $1,000 in the index and $2,000 in the database. Our first instinct was that there was a race condition at play. We had very recently migrated our apartment data from MongoDB to SQL, and something about this infrastructure change wasn't behaving correctly.

# Diagnosis
Typically race conditions only manifest under very particular conditions, and those conditions tend to occur in production environments where multiple users and processes are doing things simultaneously. You can't just drop a breakpoint into your code and figure out where a race condition is.

In order to track this issue down we turned to a feature of [NewRelic](https://newrelic.com/) called [custom events](https://docs.newrelic.com/docs/insights/insights-data-sources/custom-data/insert-custom-events-insights-api). Custom events allow you to log events within your code and then search for them using NewRelic's Insight's interface.

I opened up the code responsible for indexing records to ElasticSearch as they were saved, and injected this bit of Ruby:

```
if self.class == Apartment
…
::NewRelic::Agent.record_custom_event(
'ApartmentIndex',
event_params
)
end
```
For the sake readability I left out some setup code, namely the `event_params` variable. This variable is a hash that can contain whatever data you think you will need to debug your particular issue. Think of it as capturing the context of your code at the time that the event is hit. In our case we included the current apartment's ID, the response back from the ElasticSearch server, a snapshot of the apartment's attributes, and a current stack trace. For those curious, in Ruby, you can grab a current stack trace using `caller_locations(0)`.

With this code in place we could now begin registering searchable event data every time an apartment record was indexed to ElasticSearch. In addition, we also added a scheduled process that would run a few times a day and look for inconsistencies between apartment records in our SQL database and records in ElasticSearch. If it found one it would fix the issue and send an alert to our alerting service, triggering an email to the dev team and creating a snapshot of the apartment's data.

The relevant part of this "fixer" code is the alert notification:
```
AlertNotifier.perform(
error_class: Apartment,
error_message: 'Apartment ES index and db table out of sync.',
context: { apartment: apartment.to_hash }
)
```
Fortunately Rails makes it very easy to convert any `ActiveRecord` object to a hash using the `to_hash` method, making it simple to pass that data snapshot over to our alerting service.

With these two pieces of code in place, we now had the ability to triangulate and diagnose synchronization errors: when one occurred the dev team would receive an email and a snapshot of the apartment's data. We could then take the offending apartment's ID and run a query in NewRelic Insights to obtain a history of that apartment's indexing attempts, along with a snapshot of its data for each attempt:

`SELECT * from ApartmentIndex where id=1021570 since 1 day ago`

# The Answer
Upon investigating this log for the next alert we received, it became obvious that multiple indexes for the same apartment would sometimes cluster together. The stack traces we recorded in the NewRelic events allowed us to pinpoint down to the line number exactly where in the code these indexes were happening. In addition, by recording the ElasticSearch server's response in the `event_params`, we saw that sometimes the `version` of the index, a counter that ElasticSearch increments each time an index is updated, would sometimes skip a number. This meant there were indexes happening outside the central place we had injected our logging.

We ended up discovering three issues feeding the race condition:

Jobs queued after an apartment was saved would sometimes need to reindex the apartment, but they were reading from a slave database, meaning they would sometimes read outdated data that had not yet been replicated from the master database to the slave.
Some of these asynchronous jobs were queued from `after_save` callbacks. In Rails these callbacks run before the database transaction has finished, meaning that if the job gets picked up and executed by a worker quick enough, it would read outdated data.
There was a "reindex on failure" job that attempted to reindex records if a connection error to the ElasticSearch server failed. These were rare, but happened a few times a day, and were the source of our "skipped versions". They indexed directly to ElasticSearch instead of going through our library. This was done to prevent an infinite loop of job creation in case the connection issues persisted for an extended period. This job was also queued from an `after_save` callback, meaning its reindex attempt could also read outdated data.
Once we had identified the issues and created user stories for them, implementing the fixes was fairly straightforward. We ensured that the jobs read from the master database, and we moved our job queuing from `after_save` callbacks to `after_commit` callbacks, which don't run until the database transaction has finished.

Our alerting service paints a beautiful picture of these errors as the fixes were implemented:

![the issue is fixed](/images/zillow-bug-fixed.png)

# Conclusion

While these problems and solutions are interesting and perhaps helpful to other Ruby on Rails developers, I believe the true lesson learned is applicable to developers on any platform: lean into your logging services to diagnose difficult production problems, like race conditions. The debugger isn't always going to be helpful, and ssh-ing into a production console to manually tinker is risky, time consuming, and as a best practice probably shouldn't even be an option available to you.

If we had not used NewRelic and our alert service to track down these errors, we might still be investigating their cause.

When most of us were just getting started as developers we tended to debug our programs by littering them with print lines. Eventually we graduated to using a real debugger. In some ways these logging solutions can feel like a step back to those primal print lines - but it's not. Log streams are [one of the twelve factors](https://12factor.net/logs) of a twelve factor app. They tell the history of your application. They tell a story of what it was thinking at any given moment, and best of all they are searchable.

There's no need to guess at what's happening in production when the tools you have available essentially turn it into a glass box. Whether it's NewRelic custom events, [Graylog2](https://www.graylog.org/), [Splunk](https://www.splunk.com/en_us/solutions/solution-areas/log-management.html), [ELK](https://www.elastic.co/webinars/introduction-elk-stack), or one of the myriad other logging solutions, just be sure that your application's story is being written somewhere. More importantly, be sure that you're reading it.