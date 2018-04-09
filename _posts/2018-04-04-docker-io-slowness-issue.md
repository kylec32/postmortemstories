---
layout: post
title: "ThoughtSpot: Another reason why your Docker containers may be slow"
description: "Steps taken to debug an issue with docker slowness when multiple containers were deployed"
tags: [golang, docker, linux, kernal, perf, container]
comments: false
author: Maxim Leonovich
author_link: https://hackernoon.com/@pacavaca?source=post_header_lockup
---

_[Originally Posted On Hackernoon](https://hackernoon.com/another-reason-why-your-docker-containers-may-be-slow-d37207dec27f)_

In my last [blog post](https://hackernoon.com/kubernetes-for-dev-infrastructure-40b9175cb8c0) I was talking about Kubernetes and how [ThoughtSpot](https://thoughtspot.com/) uses it for its dev infrastructure needs. Today I’d like to follow up on that with a rather short but interesting debugging story that happened recently. It re-iterates on the fact that containerization != virtualization and demonstrates how containerized processes can compete for resources even if all cgroup limits are set to reasonable values, and there’s plenty of computing power available on the host machine.


So, we were using our internal Kubernetes cluster to [run a bunch of CI/CD and dev-related workflows](https://hackernoon.com/kubernetes-for-dev-infrastructure-40b9175cb8c0), and everything was going great except one thing: when launching Dockerized copies of our product, we saw a much much worse performance than we expected. Each of our containers had generous CPU and memory limits of 5 CPU / 30 Gb RAM set through the Pod configuration. On a virtual machine that would be more than enough for all the queries upon our tiny (10 Kb) test dataset to fly. And on Docker & Kubernetes, we were able to launch only 3–4 copies of a product on a 72 CPU / 512 Gb RAM machine, before things were becoming too slow. Queries that used to finish in a few milliseconds were now taking a second or two, and that was causing all kinds of failures in our CI pipelines. So, we dove into debugging.

The usual suspects were, of course, configuration errors that we might have made while packaging our product in Docker. However, we couldn’t find anything, that might have caused any slowness, compared to VM or bare metal installations. Everything looked correct. As a next step, we ran all kinds of tests from a [Sysbench](https://github.com/akopytov/sysbench) package. We’ve tested CPU, disk, RAM performance — nothing looked any different from bare metal. Some services in our product save detailed traces of all activities, which can later be used for performance profiling. Usually, if we’re starving on one of the resources (CPU, RAM, disk, network), there would be significant skews in timing for some calls, and that’s how we determine where the slowness comes from. In this case, however, nothing looked wrong. All the timing proportions were the same as in a healthy configuration, except that every single call was significantly slower than on bare metal. Nothing was pointing us in the direction of the actual problem, and we were ready to give up, but then we found this: [https://sysdig.com/blog/container-isolation-gone-wrong/](https://sysdig.com/blog/container-isolation-gone-wrong/).

In this article, the author analyzes a similarly mysterious case, where two, supposedly lightweight, processes were killing each other, when running inside Docker on the same machine, even though resource limits were set to very conservative values. Two key takeaways for us were:

1. The root cause of his problem ended up being in the Linux kernel. Due to a kernel dentry cache design, the behavior of one process was making __d_lookup_loop kernel call significantly slower, and this was directly affecting the performance of the other.
2. The author used perf to track down a kernel bug — a beautiful debugging tool, which we never used before (what a shame!).
> perf (sometimes called perf_events or perf tools, originally Performance Counters for Linux, PCL) is a performance analyzing tool in Linux, available from Linux kernel version 2.6.31. Userspace controlling utility, named perf, is accessed from the command line and provides a number of subcommands; it is capable of statistical profiling of the entire system (both kernel and userland code).
It supports hardware performance counters, tracepoints, software performance counters (e.g. hrtimer), and dynamic probes (for example, kprobes or uprobes). In 2012, two IBM engineers recognized perf (along with OProfile) as one of the two most commonly used performance counter profiling tools on Linux

So, we thought: why can’t it be something similar in our case? We run hundreds of different processes in our containers and they’re all sharing the same kernel. There must be some bottlenecks! Armed with perf in both hands, we resumed our debugging and it led us to some interesting findings.

Below are perf recording of a few tens of seconds of ThoughtSpot running on a healthy (fast) machine (left side) and inside a container (right side).

![good container vs bad contain](/images/thoughtspot_perf_run.png)

We can immediately notice, that the top 5 calls on the right side are kernel related and the time is mostly spent in the kernel space, while on the left side, most of the time is spent by our own processes operating in the user space. More interestingly, a call that is taking all the time is a posix_fadvise.

> Programs can use posix_fadvise() to announce an intention to access
 file data in a specific pattern in the future, thus allowing the
 kernel to perform appropriate optimizations.

It can be used in all kinds of situations, so it doesn’t directly suggest where the problem may be coming from. However, after searching our codebase, I found only one place, which had a potential of being hit by every process in the system:

![system calls](/images/thoughtspot_system_calls.png)

It’s in the third-party logging library called glog. We use it all over the project, and this particular line is in the `LogFileObject::Write` — perhaps the most critical path in the whole library. It is called for every “log to file” event and multiple instances of our product might be logging very intensively. A quick look at the source code suggests that the fadvise part can be disabled by setting a `--drop_log_memory=false` flag:

```
if (FLAGS_drop_log_memory) {
 if (file_length_ >= logging::kPageSize) {
   // don’t evict the most recent page
   uint32 len = file_length_ & ~(logging::kPageSize — 1);
   posix_fadvise(fileno(file_), 0, len, POSIX_FADV_DONTNEED);
 }
}
```

which we immediately tried and… bingo!

![working code](/images/thoughtspot_successful_fix.png)

What was previously taking up to a few seconds is now down to just *8* (eight!) milliseconds. A little bit of Googling took us to [https://issues.apache.org/jira/browse/MESOS-920](https://issues.apache.org/jira/browse/MESOS-920) and [https://github.com/google/glog/pull/145](https://github.com/google/glog/pull/145), which further confirmed that this was indeed the root cause of the slowness. Most probably, it was affecting us even on VMs or bare metal, but because there we had only one copy of each process per machine/kernel, the rate at which they were calling fadvise was several times slower, and thus not adding significant overhead. Increasing the number of logging processes by 3–4 times, while letting them all share the same kernel — that’s what caused fadvise to become a real bottleneck.

### Conclusions
While it’s definitely not a new discovery, most people still don’t keep in mind that in the case of containers, “isolated” processes compete not only for *CPU*, *RAM*, *disk*, and *network* but also for all kinds of *kernel resources*. And, because the kernel is unbelievably complex, inefficiencies may occur in the most unexpected places (like a `__d_lookup_loop` from [Sysdig’s article](https://sysdig.com/blog/container-isolation-gone-wrong/)). This by no means concludes that containers are worse or better than traditional virtualization — it’s an excellent tool for its purpose. We should just all be constantly aware of a kernel being a shared resource, and be prepared to debug weird collisions in the kernel space. Furthermore, those collisions are excellent opportunities for intruders to break through the _“lightweight”_ isolation and create all kinds of covert channels between containers. Finally, `perf` is a wonderful tool that can show you what’s all going on in your system and help you debug all kinds of performance issues. If you’re planning to run high-load applications on Docker, you definitely should invest time in learning `perf`.