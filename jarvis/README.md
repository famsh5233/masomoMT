# Masomo JARVIS

The AI agents behind **Masomo Speak**, an AI English speaking coach that explains your mistakes in
your own language. See [`docs/BUSINESS_PLAN.md`](../docs/BUSINESS_PLAN.md) for why this product,
who pays, and the numbers.

JARVIS is five agents, each with one job. They don't run the business alone. They do the repeat
work, and you check anything that involves money or goes out under the brand.

| Agent | Job | Runs | Human step |
|---|---|---|---|
| **Mwalimu** (`agents/tutor.py`) | The product: role-play conversations, corrections, explanations in the learner's language, level tracking. Enforces daily limits so AI cost stays below the price. | Live, `POST /v1/tutor/chat` | none |
| **Lesson factory** (`agents/content.py`) | Writes each week's lesson pack: vocabulary, phrases, dialogue, grammar, speaking tasks, quiz. 12-week "English for work" curriculum. | `jarvis lessons`, `jarvis daily` | Read each lesson before it goes live |
| **Growth** (`agents/growth.py`) | Daily TikTok/Reels/Shorts scripts, WhatsApp posts and paid ad variants, saved as Markdown + CSV. | `jarvis growth`, `jarvis daily` | Film or post it yourself |
| **Support** (`agents/support.py`) | Answers customers using their real account and payment records. Sends refunds and "I paid but nothing happened" cases to a human. | `POST /v1/support`, `jarvis support` | Handle escalated tickets |
| **Analyst** (`agents/analyst.py`) | MRR, paying users, churn, conversion, AI cost, gross margin, progress to $1,000 MRR, and next week's actions. | `jarvis report`, `jarvis daily`, `GET /v1/admin/report` | Decide |

Payments:
- **Tanzania mobile money** (`payments/azampay.py`): M-Pesa, Mixx by Yas (Tigo Pesa), Airtel Money, HaloPesa and AzamPesa through one AzamPay integration. The customer gets a PIN prompt on their phone, and Pro turns on automatically when the payment clears.
- **Everywhere else** (`payments/play.py`): Google Play subscriptions, verified and acknowledged on the server.

## Run locally

```bash
cd jarvis
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # add ANTHROPIC_API_KEY at minimum
set -a; . ./.env; set +a
export JARVIS_DB=jarvis.db JARVIS_CONTENT_DIR=content

pytest -q                               # 24 offline tests, no API key needed
python -m jarvis tutor --lang sw        # talk to Mwalimu in the terminal
python -m jarvis lessons --weeks 1-2    # write lesson packs to content/sw/
python -m jarvis growth --days 7        # content calendar to ops/marketing/
python -m jarvis report                 # business numbers
uvicorn jarvis.server:app --reload      # API on :8000, docs at /docs
```

## Deploy (about $6–12 a month)

1. Get a small VPS (1 vCPU, 1 GB RAM is plenty to start) and point `api.masomo.co.tz` at it.
2. `docker build -t masomo-jarvis . && docker run -d --restart=always --env-file .env -v /srv/masomo:/data -p 127.0.0.1:8000:8000 masomo-jarvis`
3. Put Caddy or nginx in front for HTTPS (Caddy: `api.masomo.co.tz { reverse_proxy 127.0.0.1:8000 }`).
4. Schedule the daily routine at 05:00 EAT (02:00 UTC). This crontab line runs it:
   `0 2 * * * docker exec $(docker ps -qf ancestor=masomo-jarvis) python -m jarvis daily --out /data/ops >> /var/log/jarvis.log 2>&1`
5. Back up `/srv/masomo/jarvis.db` every night, for example with `sqlite3 .backup` to object storage.

## API (what the Flutter app calls)

| Method | Path | Notes |
|---|---|---|
| POST | `/v1/auth/start` | `{phone, country}` sends a 6-digit SMS code. Numbers are limited to the countries in `JARVIS_OTP_COUNTRIES`, with at most 3 codes per hour. **429** when the limit is hit |
| POST | `/v1/auth/verify` | `{phone, country, code}` returns `{token, user_id, is_new}`. Each code works once, with 5 tries; logging in again replaces the previous token |
| POST | `/v1/auth/logout` | Invalidates the token |
| GET / PATCH | `/v1/me` | Profile, Pro status and conversations left today. PATCH changes `name`, `native_lang` and `level` |
| POST | `/v1/tutor/chat` | `{message, scenario}` returns `{reply, corrected, mistakes[], tip, score, level, turns_left}`. **429** `daily_limit` when today's limit is used up |
| GET | `/v1/lessons` | The 12 weeks, with `title`, `published` and `locked` |
| GET | `/v1/lessons/{week}` | Week 1 is free; later weeks return **402** without Pro. Weeks 1–2 ship with the server (`seed_content/`); later weeks come from `jarvis lessons` |
| GET | `/v1/videos`, `/v1/videos/{week}` | Existing Masomo videos from the old masomo.co.tz API, with the same Pro rule |
| GET | `/v1/catalog` | Plans, languages and scenarios |
| POST | `/v1/pay/mobile` | `{plan: tz_week\|tz_month\|tz_quarter, provider: mpesa\|mixx\|airtel\|halopesa\|azampesa, phone}` |
| GET | `/v1/pay/status/{id}` | The app polls this after checkout |
| POST | `/v1/pay/azampay/callback?key=…` | AzamPay calls this |
| POST | `/v1/pay/play/verify` | `{purchase_token}` after a Google Play purchase |
| POST | `/v1/support` | `{message}` |
| GET | `/v1/admin/report` | Header `X-Admin-Key` |

In the app, speech-to-text and text-to-speech stay **on the device**. The server sends and
receives text only, which is what keeps each conversation turn at a fraction of a cent.

## Development and testing without real services

- `JARVIS_ENV=dev JARVIS_LLM=demo JARVIS_SMS_PROVIDER=console` gives a rule-based tutor, and login
  codes are returned as `dev_code` in the API response. The server refuses demo mode unless
  `JARVIS_ENV=dev`. In production (the default) the console SMS provider returns 503 and never
  shows a code.
- `devtools/mock_azampay.py` stands in for AzamPay and the old video API. It accepts a checkout,
  then calls back like a customer entering their PIN. Numbers ending in 9 decline.
- `devtools/e2e.sh` starts both, then runs the app's real HTTP client through a whole learner
  journey: login, tutor, lessons, videos, payment, Pro, support and logout. With `E2E_UI=1` it
  also clicks through the web build in Chromium and saves screenshots.

## Before you take real money

- [ ] Run the full AzamPay flow in their sandbox: checkout, PIN prompt, callback, Pro active. Then switch the URLs to production.
- [ ] Register the callback URL with `?key=` set to `AZAMPAY_CALLBACK_SECRET`.
- [ ] Open an Africa's Talking account and register a sender ID. Set `JARVIS_SMS_PROVIDER=africastalking` and send yourself a login code.
- [ ] Register as a data controller with Tanzania's PDPC and publish a privacy policy at the URL the app links to (`PRIVACY_URL`; the default is masomo.co.tz/privacy).
- [ ] Set a monthly spend limit on your Anthropic account. Generate and review lessons 3–12 (`python -m jarvis lessons --weeks 3-12`).
- [ ] Check that `https://masomo.co.tz/api/week_videos?week=1` still returns the video list, or point `JARVIS_LEGACY_VIDEOS_URL` at the new location. That old endpoint needs no login, so anyone who finds it can list the Pro videos. Restrict it to this server's IP address, or move the videos behind signed links.
- [ ] Before going live, confirm with AzamPay whether you can check a transaction's status through their API. If so, confirm each callback that way as well. For now a callback is trusted if it carries the secret key and the right amount.
