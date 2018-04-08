---
layout: post
title: "Github DDoS Attack"
description: "Explanation of What Happened During the March 1st 2018 Github DDoS Memcachd attack."
tags: [github, cloudflare, ddos, memcached]
comments: false
author: Sam Kottler
author_link: https://github.com/skottler
---

_[Originally Posted On the GitHub Engineering Blog](https://githubengineering.com/ddos-incident-report/)_

On Wednesday, February 28, 2018 GitHub.com was unavailable from 17:21 to 17:26 UTC and intermittently unavailable from 17:26 to 17:30 UTC due to a distributed denial-of-service (DDoS) attack. We understand how much you rely on GitHub and we know the availability of our service is of critical importance to our users. To note, at no point was the confidentiality or integrity of your data at risk. We are sorry for the impact of this incident and would like to describe the event, the efforts we’ve taken to drive availability, and how we aim to improve response and mitigation moving forward.

## Background
Cloudflare described an amplification vector using memcached over UDP in their blog post this week, [“Memcrashed - Major amplification attacks from UDP port 11211”](https://blog.cloudflare.com/memcrashed-major-amplification-attacks-from-port-11211/). The attack works by abusing memcached instances that are inadvertently accessible on the public internet with UDP support enabled. Spoofing of IP addresses allows memcached’s responses to be targeted against another address, like ones used to serve GitHub.com, and send more data toward the target than needs to be sent by the unspoofed source. The vulnerability via misconfiguration described in the post is somewhat unique amongst that class of attacks because the amplification factor is up to 51,000, meaning that for each byte sent by the attacker, up to 51KB is sent toward the target.

Over the past year we have deployed additional transit to our facilities. We’ve more than doubled our transit capacity during that time, which has allowed us to withstand certain volumetric attacks without impact to users. We’re continuing to deploy additional transit capacity and [develop robust peering relationships across a diverse set of exchanges](https://githubengineering.com/transit-and-peering-how-your-requests-reach-github/). Even still, attacks like this sometimes require the help of partners with larger transit networks to provide blocking and filtering.

The incident
Between 17:21 and 17:30 UTC on February 28th we identified and mitigated a significant volumetric DDoS attack. The attack originated from over a thousand different autonomous systems (ASNs) across tens of thousands of unique endpoints. It was an amplification attack using the memcached-based approach described above that peaked at 1.35Tbps via 126.9 million packets per second.

At 17:21 UTC our network monitoring system detected an anomaly in the ratio of ingress to egress traffic and notified the on-call engineer and others in our chat system. This graph shows inbound versus outbound throughput over transit links:

![more inbound than outbound traffic graph](/images/github-ddos-graph.png)

Given the increase in inbound transit bandwidth to over 100Gbps in one of our facilities, the decision was made to move traffic to Akamai, who could help provide additional edge network capacity. At 17:26 UTC the command was initiated via our ChatOps tooling to withdraw BGP announcements over transit providers and announce AS36459 exclusively over our links to Akamai. Routes reconverged in the next few minutes and access control lists mitigated the attack at their border. Monitoring of transit bandwidth levels and load balancer response codes indicated a full recovery at 17:30 UTC. At 17:34 UTC routes to internet exchanges were withdrawn as a follow-up to shift an additional 40Gbps away from our edge.

![graph showing traffic movement off exchanges](/images/github-ddos-graph-2.png)

The first portion of the attack peaked at 1.35Tbps and there was a second 400Gbps spike a little after 18:00 UTC. This graph provided by Akamai shows inbound traffic in bits per second that reached their edge:

![traffic to akamai edge](/images/github-ddos-akamai-edge.png)


## Next steps

Making GitHub’s edge infrastructure more resilient to current and future conditions of the internet and less dependent upon human involvement requires better automated intervention. We’re investigating the use of our monitoring infrastructure to automate enabling DDoS mitigation providers and will continue to measure our response times to incidents like this with a goal of reducing mean time to recovery (MTTR).

We’re going to continue to expand our edge network and strive to identify and mitigate new attack vectors before they affect your workflow on GitHub.com.

We know how much you rely on GitHub for your projects and businesses to succeed. We will continue to analyze this and other events that impact our availability, build better detection systems, and streamline response.