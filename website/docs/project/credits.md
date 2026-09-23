---
title: Credits, and what this is not
description: A port of TanStack Query, with thanks — unaffiliated with TanStack, and written by AI.
---

# Credits, and what this is not

## It is a port

Not "inspired by". Not "in the spirit of". A **port of [TanStack
Query](https://tanstack.com/query)**: the behaviour is TanStack Query's, the
architecture is its, the option names are its where Dart allowed it, and its
own test suite is ported case for case and run against this code. Where
query_kit deliberately behaves differently, the difference is written down
with its reason — see [differences from TanStack
Query](../reference/differences-from-tanstack.md).

If you know TanStack Query, you already know this library. That is the goal,
and [how it is checked](fidelity.md) is the only interesting thing about the
project.

## Thank you

**To Tanner Linsley, to TkDodo, and to everyone who has built, maintained,
documented and supported TanStack Query.**

This repository exists for one reason: we used TanStack Query, we loved it, and
we wanted the same thing in Flutter. Server state is a genuinely hard problem
that most teams end up solving badly and by accident, and TanStack Query is the
answer that made it look easy. Everything good in here is an idea we took from
them.

It is published under their MIT licence. Each package carries Tanner Linsley's
copyright line and the MIT permission notice in `LICENSE-TANSTACK`, because a
port that translates `query-core` and its test suite line by line is a copy of
substantial portions of the original, and the licence says so.

## It is not theirs

:::danger Not affiliated with TanStack
This project is **not affiliated with, endorsed by, reviewed by, or connected
in any way to** Tanner Linsley, the TanStack team, or the TanStack
organisation. They have not seen it. They have no responsibility for it. The
name similarity, where any exists, is descriptive — it says what this is a port
*of*, not who made it.

**Please do not take problems with this package to them.** Bugs, questions and
complaints belong in [this repository's
issues](https://github.com/KoTTi97/flutter_query/issues), and nowhere near
TanStack's.
:::

The package name here is deliberately not TanStack's:
[`docs/releasing.md`](https://github.com/KoTTi97/flutter_query/blob/main/docs/releasing.md)
explains why, and the [naming research](https://github.com/KoTTi97/flutter_query/blob/main/docs/research/package-naming-and-affiliation.md)
records what was actually checked — pub.dev's rules, what TanStack has and has
not said about community ports, and how ports in six other languages named
themselves.

## It was written by AI

:::warning An AI-written project
Effectively **all** of the code, the tests and the documentation in this
repository were written by AI agents, working from a plan the agents also
wrote. A human is in the loop only rarely.
:::

That is not a disclaimer bolted on afterwards; it is how the project was run,
and the repository records it. Every decision is settled by an agent, and the
record states the options, the answer, and why it beats the alternatives, so
any call can be reopened from the record alone. The plan, its decisions and
the research behind them are all public.

What the human actually decided is a short list: the destination; that the
binding's API shape would offer four equal call styles with no recommended
default; and that neither published package may require a third-party
dependency. Everything else — the architecture, the divergences, the test
strategy, this sentence — was decided by an agent.

**What stands in for human review is adversarial, and deliberately so:**

- **TanStack Query's own test suite**, ported case for case. It is the one
  referee that cannot be talked round.
- **Repeated external deep-dive reviews**, each by a fresh reviewer with no
  memory of the decisions — and a fresh review of every fix.
- **A standing rule that no reported finding is acted on until it has been
  reproduced.** Findings that do not reproduce are written down too, with the
  disproof.
- **Example applications** that use the library for real, and a first
  integration into a production app.

What each of these found is on [how fidelity is proven](fidelity.md).

None of that makes the code correct. It does mean the claims on this site are
the kind you can check, and every one of them names the file that would prove
it wrong. Judge it on that.
