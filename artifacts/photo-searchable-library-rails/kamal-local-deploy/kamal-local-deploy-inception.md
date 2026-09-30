---
title: Local Kamal Deploy Loop
tags:
  - inception
  - kamal-local-deploy
  - kamal
  - deployment
  - docker
keywords: [kamal, deploy, local, thruster, registry, ssh, docker]
incepted: 2026-09-30

# Local Kamal Deploy Loop

## Idea

> (executive summary — written at distill; leave placeholder during interview)

## Goal

> (success criteria and feature list — written at distill; leave placeholder during interview)

## Interview Results

**What should this deliver?**
A genuinely runnable local Kamal deploy: `bin/kamal deploy -d local` that exercises the full proxy/orchestration loop against this machine, not just config parsing.

**How does Kamal orchestrate?**
Kamal deploys over SSH to the target, pushes the image to a registry, and pulls it on the target. For a local run on macOS this means: enable `sshd`/Remote Login, authorize the SSH key, run a throwaway registry (`registry:2` on `:5000` or `:5555`) shared by both sides, and be aware the Kamal proxy binds :80/:443.

**How should this fit with the rest of the project?**
`bin/kamal deploy -d local` picks up `config/deploy.local.yml`, merged over the base `config/deploy.yml`. The sidecar accessory is booted separately with `bin/kamal accessory boot sidecar`. It must not collide with the `bin/dev-docker` stack (don't run both at once). The README should document this only after it is verified working.

## Timeline
(Consider the time taken to complete the task. Include any timelines or deadlines that are expected, but leave placeholders during the interview.)