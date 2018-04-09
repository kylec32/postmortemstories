---
layout: post
title: "CircleCI: 
3 Mistakes We Made Moving to a Microservices Architecture"
description: "During CircleCI's move away from a monolithic architecture, they came up with three sources of friction in their microservices migration. They also developed ways to address them"
tags: [microservices, organization change, decision making, empowerment, guilds]
comments: false
author: Rob Zuber
author_link: https://www.infoworld.com/author/Rob-Zuber/
---

_[Originally Posted On Infoworld](https://www.infoworld.com/article/3268186/enterprise-architecture/3-mistakes-we-made-moving-to-a-microservices-architecture.html)_


My company, CircleCI, is a big believer in the blameless postmortem—the idea that when you discuss a project and take emotion out of the picture, you create a true learning experience. Following our migration to a microservices architecture, we had a good opportunity to run a blameless postmortem on what we did right and wrong, and what we’d do differently next time. If you’re thinking about starting the journey to microservices, I’d like to share some advice for creating a smoother transition.

Our move away from monolithic architecture took on urgency when we had a 24-hour outage in 2015. We wanted to be cautious: We’d heard a lot of tales of poor decision-making when transitioning full-stop into microservices. On the other hand, incremental changes to architecture weren’t bringing the transformation we needed. Early wins breaking up our architecture gave us confidence that this was the right direction for our team, and we decided to go all in. Almost immediately, the wheels started coming off the wagon. Engineering productivity ground to a halt. We realized we were throwing people into an unfamiliar environment—like moving from the small-town comfort of the monolith to the unknown microservices big city.

In our post-mortem, we came up with three sources of friction in our microservices migration, and we developed ways to address them.

# 1. Decision-making
“Analysis paralysis” is being faced with a decision that’s so complex that you spend ages considering all the options without pulling the trigger on anything. The solution is to make hard decisions early on, and then reduce future decision-making to exceptions only—choosing to go in another direction only when that initial decision fails you.

In our case, we said to our engineers, “We’re a Clojure shop. It’s not an option for you to decide what language or stack you’re going to use. We all know Clojure, and it has treated us well.”

In deciding to use gRPC, Postgres, Docker, and Kubernetes, we felt like we had agreed on a common stack that would serve the project. It turns out that the nuances of those decisions were more complex than we anticipated: What version of Clojure? What libraries?

While we thought we had made our important decisions upfront, we didn’t anticipate the depth of decisions we were going to run into—we weren’t even close. So, what did we learn? We could have spent more time creating guidance upfront, but in an agile world, that isn’t a great investment of time. Instead, your team needs a very clear definition of how to make decisions, who can make them, and how to share those decisions efficiently with the rest of the team. Because you can’t anticipate every decision at the outset, make sure you have clear protocols to smoothly handle the unexpected.

# 2. Novelty
Engineers love new stuff. Sometimes, it’s because the old stuff hasn’t satisfactorily solved our problems, in which case it makes sense to seek new solutions. But there are times when old stuff might be the right choice for your microservices project. Moving to microservices is on its own a significant change, so limiting additional changes is a wise strategy.

 
[Read the rest on InfoWorld](https://www.infoworld.com/article/3268186/enterprise-architecture/3-mistakes-we-made-moving-to-a-microservices-architecture.html)