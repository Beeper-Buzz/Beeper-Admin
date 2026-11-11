# DOCKER SETUP ✻

This repo is using Spree 4.2.4

# Local Docker Development
This repo is using Spree 4.2.4

This should only have to be done once, or whenever the Gemfile is updated.

First try this:

```shell
./docker-build.sh
```

The manual way:

```shell
docker-compose build
```

```shell
docker-compose up
```

DNA Admin should now be available at localhost:8080,
but it probably needs to be set up first.

## Set up system

In a new terminal run:

```shell
docker-compose exec web rails db:create db:schema:load db:migrate &&
docker-compose exec -e ADMIN_EMAIL=spree@example.com -e ADMIN_PASSWORD=spree123 web rails db:seed &&
docker-compose exec web rails spree_sample:load &&
docker-compose restart
```

OPTIONAL: Create a new admin user.  This can be used to reset the
admin user also:

```shell
docker-compose exec web rails spree_auth:admin:create
```

default is:

email: spree@example.com

password: spree123

## Reset DB

This will reset the existing database back to blank.

```shell
docker-compose exec web rails db:reset railties:install:migrations db:migrate spree_sample:load db:seed
```

You could also blow away all the DB files.  WARNING! You'll have to start
the install over again if you do this.

```shell
sudo rm -rf tmp/db
```

## Rails Console

`docker exec -it dna-admin_web_1 bin/rails console`

## Extensions

The system uses 3 spree extensions

* `spree_reffiliate` (Thanks @Gaurav2728)
  [github](https://github.com/Gaurav2728/spree_reffiliate)
* `spree_loyalty_points` (Thanks @Gaurav2728)
  [github](https://github.com/Gaurav2728/spree_loyalty_points)
* `spree_static_content`
  [github](https://github.com/spree-contrib/spree_static_content)
* `spree_digital`
  [github](https://github.com/spree-contrib/spree_digital)
* `spree_promo_users_codes`
  [github](https://github.com/vinsol-spree-contrib/spree_promo_users_codes)

Each one is installed _after_ spree, with it's own migrations generated using a
specific `bundle exec rails g` command, which can be found on the README of the github
page for each project.  This only needs to be done once after spree is installed or upgraded.

## CLI Scripts

`./tools/docker-scripts.sh reload_db`

## Swagger UI

## Scripts

1. Generate **Affiliate Codes** for Existing Users: `bundle exec rake reffiliate:generate`
1. Create or reset a **New Admin User**: `docker-compose exec web rails spree_auth:admin:create`
1. Load Spree sample data & seed data: `rake db:seed && rails spree_sample:load`

## Deploy

This uses heroku ruby buildpack on the heroku-20 stack.  The `master` branch
on github is hooked in to the deployment.

### Heroku

1. Create a new pipeline & app
2. Add Postgres: `heroku addons:create heroku-postgresql:essential-0 -a dna-admin-staging`
3. Grab ENV vars from another app: `heroku config -s -a dna-admin-staging > config.txt`
4. Grab the DB creds from <heroku.com>, add them to `config.txt`
5. Edit other vars locally
6. Upload vars to app: `cat config.txt | tr '\n' ' ' | xargs heroku config:set -a dna-admin-staging`
7. Set stack: `heroku stack:set heroku-18 -a dna-admin-staging`
8. Set buildpack: `heroku buildpacks:add heroku/ruby`
9. Setup DB: `heroku run rake db:schema:load db:migrate -a dna-admin-staging`
10. Seed DB: `heroku run -a dna-admin-staging rake db:seed`
11. Load Sample Data: `heroku run -a dna-admin-staging rake spree_sample:load`
12. Asset Precompile: `heroku run -a dna-admin-staging rake assets:precompile`

Alternate (container) deploy:

1. `./docker-build.sh`
1. `heroku stack:set container -a dna-admin-prod`
1. `heroku container:push dna-admin-web-1 -a dna-admin-prod`
1. `heroku container:release web -a dna-admin-prod`
1. `heroku config:set SECRET_KEY_BASE=$(docker-compose exec dna-admin-web-1 rails secret) -a kry-admin-prod`

Git: <https://github.com/POL-Clothing/pol-admin>

### Testing Production Settings

To test the production settings locally (used to test things like the S3 buckets
for active storage), you need to set environment variables directly in
the `docker-compose.yml` file.  The production environment is configured
to NOT use `.env` files.

To do this, apply the following patch to `docker-compose.yml` (after filling
in real values for the keys and bucket name):

```--- docker-compose.yml.orig     2021-06-02 10:50:59.011383071 -0400
+++ docker-compose.yml  2021-06-02 10:51:03.267414021 -0400
@@ -16,4 +16,10 @@
     depends_on:
       - db
     environment:
-      DATABASE_URL: postgres://postgres:password@db:5432/dna_admin_development
+      DATABASE_URL: postgres://postgres:password@db:5432/dna_admin_production
+      RAILS_ENV: production
+      AWS_REGION_NAME: us-west-1
+      AWS_BUCKET_NAME:
+      AWS_ACCESS_KEY_ID:
+      AWS_SECRET_ACCESS_KEY:
+      RAILS_SERVE_STATIC_FILES: 1
```

## Keeping Your Code Updated:

When there are lots of active changes occuring on this repo, make sure to regularly:

1. Commit (or stash) your local changes on your branch
1. `git fetch origin`
1. `git checkout main`
1. `git pull origin main`
1. `git checkout <your_branch>`
1. `git merge main`
1. Fix merge conflicts (if any)
1. `git add .`
1. `git commit -m 'merge in latest main'`

Done!
…now you will be up-to-date with latest code. Do this before you submit your PR, and you can be sure it will be a clean merge.

http://localhost:8080/apidocs/swagger_ui
Make sure to change the port that the UI is expecting in the search bar

## Device firmware releases

Hardware firmware is released as **bundles**: one tested set of signed images (`stm32`,
`stm32_assets`, `nrf_app`, `nrf_net`; any subset, but `stm32` and `stm32_assets` always together)
for one hardware revision (`hw_rev`, e.g. `V114`), on a channel (`internal`, `beta`, `stable`),
with a staged rollout. Code: `app/services/firmware.rb` (start there), `app/models/firmware_*.rb`,
`app/controllers/spree/api/v1/firmware/`, the admin's **Firmware** tab (`/admin/firmware`). Tables:
`firmware_bundles`, `firmware_images`, `firmware_reports`, `firmware_rate_counters`. Image files
live in the ActiveStorage S3 bucket and are handed out as presigned URLs that expire after an hour.
The server never holds a signing key: every image carries its own signature and the device
verifies it. The server checks `sha256` and `size` against the uploaded bytes, and that radio
images are MCUboot images with an ECDSA P-256 signature of the declared version.

**Endpoints**

| | Auth | What |
|---|---|---|
| `GET /api/v1/firmware/check?hw=V114&channel=stable&device=<hash>&app_version=2.7.0&stm32=1.4.0&stm32_assets=1.4.0&nrf_app=1.2.0&nrf_net=1.1.0&security_epoch=1` | none (rate-limited per device, see below) | `{ bundle: null \| { id, version, notes, min_app_version, images: [{ component, version, size, sha256, signature_key_id, url, url_expires_at, ... }] }, app_update_required, min_app_version, revoked }`. Images are only the ones that changed, in install order (`nrf_net`, `nrf_app`, `stm32_assets`, `stm32`). |
| `POST /api/v1/firmware/reports` | optional bearer (links the user) | one install result: `device`, `bundle_id`, `component`, `from_version`, `to_version`, `result` (`ok`/`failed`/`rolled_back`/`aborted`), `stage`, `error_code`, `duration_ms`, `app_version`, `platform`, `phone_model` |
| `POST /api/v1/admin/firmware/bundles` | `Authorization: Bearer $FIRMWARE_UPLOAD_TOKEN` | CI creates a **draft** (multipart; see the controller's header comment) |

`device` is the device's own SHA-256 of its unique ID (64 hex); the raw ID never reaches the
server. A device is in a rollout when `SHA-256("<device>:<bundle version>")` (first 8 bytes,
big-endian) mod 100 is below `rollout_percent`; raising the percentage only adds devices.

`security_epoch` (optional; or per component: `stm32_epoch`, `stm32_assets_epoch`, `nrf_app_epoch`,
`nrf_net_epoch`, the highest counts) is the epoch the device's bootloaders hold: no bundle of a
lower epoch is offered. Clients should send it. Without it, a device whose versions match a known
bundle still gets that bundle's epoch as the floor, but one whose versions match no known bundle
(a dev build, an odd partial state) has no floor and may be offered an older bundle its
bootloaders then refuse.

`check` with a `device` hash is limited per device (240/h) with a loose per-IP ceiling (2000/h),
so phones sharing a carrier NAT address aren't refused; without `device` (a recovery page that can't read it) it is
limited strictly per IP (240/h). Reports: 120/h per IP and 100/day per device.

**Publish a release**

1. CI (or **New draft bundle** in the tab) creates a draft with its images. Check the versions,
   sizes and release notes on the bundle page.
2. Set the channel and rollout % (start small, e.g. 5), then **Publish**. From then on the
   hardware revision, version, security epoch and images are fixed.
3. Read the install reports on the bundle page, then raise the rollout (25, then 100).

A device is never offered a bundle older than the one it runs (lowering a rollout or leaving the
beta channel doesn't downgrade anyone), nor one that needs a newer app (`min_app_version`; the
answer then says `app_update_required`).

**Kill switch: Pause.** A paused bundle is offered to nobody, at once; devices that have it keep
it. **Resume** offers it again.

**Rollback.** **Revoke** a bad bundle: it is offered to nobody, devices still on it get
`revoked` in the check answer and are offered the newest good bundle, even if that is older
(downgrades are fine within a security epoch). Revoking can't be undone. To roll a fix out
forward instead, publish the previous images as a new, higher bundle version.

**CI token.** Generate a long random token (at least 32 characters, e.g.
`ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`), set it as `FIRMWARE_UPLOAD_TOKEN` in the
Heroku app's config and as a GitHub Actions secret of the firmware repo. To rotate, set
`FIRMWARE_UPLOAD_TOKEN=<new>,<old>`, switch CI to the new one, then drop the old one. The token
only creates drafts; it can't publish, edit or delete. Unset, the upload endpoint refuses every
request.

```sh
curl -fsS -X POST "$API_URL/api/v1/admin/firmware/bundles" \
  -H "Authorization: Bearer $FIRMWARE_UPLOAD_TOKEN" \
  -F hw=V114 -F version=1.5.0 -F channel=internal -F "release_notes=<notes.md" \
  -F "images[stm32][file]=@stm32.bin" -F "images[stm32][version]=1.5.0" \
  -F "images[stm32][sha256]=$(sha256sum stm32.bin | cut -d' ' -f1)" -F "images[stm32][signature_key_id]=stm32-dev" \
  -F "images[stm32_assets][file]=@assets.bin" ...
```

**Environment**

- `FIRMWARE_UPLOAD_TOKEN`: CI upload token(s), comma-separated.
- `FIRMWARE_ALLOWED_ORIGINS`: browser origins allowed to call `check` and `reports` (default
  `https://beeper.buzz,https://www.beeper.buzz`), for the USB recovery/update web page.

**Manual step for the web page:** the S3 bucket (`AWS_BUCKET_NAME`) needs a CORS rule so the
browser can `fetch()` the presigned URLs. Add to the bucket's existing rules (S3 console →
bucket → Permissions → CORS):

```json
{ "AllowedOrigins": ["https://beeper.buzz", "https://www.beeper.buzz"], "AllowedMethods": ["GET", "HEAD"],
  "AllowedHeaders": ["*"], "ExposeHeaders": ["Content-Length", "ETag"], "MaxAgeSeconds": 3600 }
```

## TODO

Other things we may need to cover:

1. Ruby version

1. System dependencies

1. Configuration

1. Database creation

1. Database initialization

1. How to run the test suite

1. Services (job queues, cache servers, search engines, etc.)

1. Deployment instructions
