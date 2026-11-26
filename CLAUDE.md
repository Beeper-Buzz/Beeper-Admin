# Beeper-Admin

The admin, CMS and API for **Beeper** (beeper.buzz) and the Beeper Δ8: the store, the creator
marketplace, profiles, AI backing tracks and the content the website and the iOS app read. It is
a fork of the DNA boilerplate [`1instinct/dna-admin`](https://github.com/1instinct/dna-admin)
(Spree 4.2.5 on Rails 6.1 and Ruby 2.7.2). Inherited conventions are in
[.github/copilot-instructions.md](.github/copilot-instructions.md), which still says "DNA Admin"
because it comes from upstream; this file says what is different about the fork.

## Where this repo sits

| Layer | Repos |
|---|---|
| Upstream boilerplate (product agnostic) | `1instinct/dna-admin` (this repo's upstream), `1instinct/dna-frontend`, `1instinct/expo-juce` |
| Beeper | **Beeper-Admin** (this repo), `Beeper-Buzz/Beeper-Frontend` (fork of dna-frontend, the website), `Beeper-Buzz/BeeperNative` (the iOS app, uses expo-juce), `Beeper-Buzz/device-rtos` (Δ8 firmware) |

## What goes here, and what goes upstream

1. Only Beeper-specific work lands here: Beeper branding, copy and URLs, the Δ8 and its
   hardware ideas, the marketplace's digital kinds (sample packs, effect presets, visualizers),
   the app's endpoints and anything that only makes sense for Beeper.
1. A feature any product on DNA could use is built in `dna-admin` first and reaches this repo
   through an upstream merge. If it has a Beeper layer, the generic core goes upstream and the
   Beeper settings are added here on top of it.
1. A bug in inherited code is fixed upstream and merged down, not patched only here.

## Keeping Beeper code separate from inherited code

Upstream merges stay easy when Beeper code lives in files upstream never has.

1. Ruby: the `Beeper::` namespace in `app/services/beeper/`, with tests in `test/services/beeper/`.
1. Configuration: `config/initializers/beeper_*.rb` sets Beeper's values on top of the generic
   modules (`beeper_marketplace.rb`, `beeper_brand.rb`). Prefer this to editing an inherited file.
1. Rake tasks: `lib/tasks/beeper_*.rake` under the `beeper:` namespace.
1. Images: `app/assets/images/beeper/`. `beeper_brand.rb` points `COMPANY_LOGO`,
   `COMPANY_BACKGROUND`, `LOGIN_BACKGROUND` and `SITE_TITLE` at Beeper's, since the inherited
   views fall back to the boilerplate's.
1. Seeds: Beeper seeds share the `db/seeds/NNN_*.rb` sequence with upstream's. When an upstream
   seed arrives with a number this fork already uses, renumber the incoming file, not the one
   already deployed.

## Merging upstream

```
git remote add upstream https://github.com/1instinct/dna-admin.git   # once
git fetch upstream master
git merge upstream/master
```

Upstream is product agnostic, so a merge can replace Beeper values in shared files (Heroku
scripts and docs, env examples, tests) with neutral ones. Keep the Beeper side in those
conflicts, and check that nothing Beeper relies on was deleted.

## Working here

1. `master` is the trunk; branch from it and open PRs against it.
1. Do not upgrade version-locked dependencies (Ruby, Rails, Spree, Puma).
1. Tests: `bundle exec rails db:test:prepare && DISABLE_SPRING=1 bundle exec rails test`
   (add `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` on macOS).
1. Deploys go to Heroku with Docker (`heroku.yml`): assets are precompiled in the image and
   migrations run in the release phase. See [HEROKU_DEPLOYMENT.md](HEROKU_DEPLOYMENT.md).

## Commits and PRs

No attribution lines (no `Co-Authored-By`, no generated-by footers). Lists use repeated `1.` so
items can be reordered without renumbering.

```
[Feature|Fix|Chore]: Sentence-case summary of the outcome, changes:
1. What changed, naming the file or symbol, and why
1. Next change
```

PR titles match the commit subject. PR bodies use `## What`, `## Why`, `## Changes` and
`## Verify` sections with `1.` lists. Say when a change has to go upstream first.
