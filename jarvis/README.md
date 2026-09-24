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

pytest -q                               # 15 offline tests, no API key needed
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
| POST | `/v1/users` | `{phone, name, native_lang, country, level}` returns `{user_id, token}`. Add SMS OTP before launch. |
| GET | `/v1/me` | Pro status and conversations left today |
| POST | `/v1/tutor/chat` | `{message, scenario}` returns `{reply, corrected, mistakes[], tip, score, level, turns_left}`. **429** with `upgrade: true` when the daily limit is reached |
| GET | `/v1/lessons/{week}` | Week 1 is free. Later weeks return **402** without Pro |
| POST | `/v1/pay/mobile` | `{plan: tz_week\|tz_month\|tz_quarter, provider: mpesa\|mixx\|airtel\|halopesa\|azampesa, phone}` |
| GET | `/v1/pay/status/{id}` | Poll after checkout |
| POST | `/v1/pay/azampay/callback?key=…` | AzamPay calls this |
| POST | `/v1/pay/play/verify` | `{purchase_token}` after Play Billing purchase |
| POST | `/v1/support` | `{message}` |
| GET | `/v1/catalog` | Plans, languages, scenarios |
| GET | `/v1/admin/report` | Header `X-Admin-Key` |

In the app, speech-to-text and text-to-speech stay **on the device**. `speech_to_text` and
`flutter_tts` are already in `pubspec.yaml`. The server sends and receives text only, which is what
keeps each conversation turn at a fraction of a cent.

## Before you take real money

- [ ] Run the full AzamPay flow in their sandbox: checkout, PIN prompt, callback, Pro active. Then switch the URLs to production.
- [ ] Register the callback URL with `?key=` set to `AZAMPAY_CALLBACK_SECRET`.
- [ ] Add SMS OTP to sign-up so a phone number actually belongs to its user.
- [ ] Register as a data controller with Tanzania's PDPC and publish a privacy policy (the app records speech).
- [ ] Set a monthly spend limit on your Anthropic account.
