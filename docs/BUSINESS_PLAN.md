# Masomo Speak: research, business plan and production plan

*Prepared 24 September 2026. Currency: USD unless marked. FX used: 1 USD ≈ 2,640 TSh.*

---

## 0. Where I push back on your brief

Your instructions ask me to challenge you first, so these come before the plan.

1. **The `famsh5233/funny` repo is empty.** It has no commits and no files, so it has nothing to
   reuse. Your only developed asset is **this repo, masomoMT**: a Flutter app that teaches English
   to Swahili speakers for TSh 2,000 a week. It has video lessons, a chatbot, speech-to-text,
   text-to-speech, a translator and a manual M-Pesa payment screen. The plan is built on that.
2. **"All around the world" from day one gets you no customers.** No one can market to eight
   billion people with a solo budget. The realistic version is a product that is global-ready
   (any native language, Google Play billing in 170+ countries) with a go-to-market that starts
   where you already have an advantage: Swahili speakers in Tanzania and Kenya. You add a new
   market only after the first one proves the numbers (Section 7).
3. **$1,000 MRR does not need "lots of customers".** It needs about **300–390 paying
   subscribers**. That is a focused, achievable target. Don't build five products to get there.
4. **"JARVIS" as a fully autonomous business-runner doesn't exist, and pretending it does is how
   money gets lost.** What I built are five working agents with narrow jobs: tutor, lessons,
   marketing, support and analytics. A human (you) still approves money, refunds and anything
   published under your brand.
5. **The current app cannot ship as it is.** Details are in Section 4. Its package ID is
   `com.example.masomoMT`, which Google Play rejects. It targets Android API 29, but Play has
   required API 36 for new apps and updates since 31 Aug 2026. It uses Flutter 1.x APIs that no
   longer exist. The payment flow asks users to send money to personal phone numbers and paste
   the SMS, which cannot scale and is easy to fake. `homepage.dart` sends a hardcoded password
   `'masomo'` with any phone number to fetch user data. If the backend accepts that, anyone can
   read any user's account. Fix these before spending on marketing.

---

## 1. What to sell

**Masomo Speak: an AI English speaking coach that explains your mistakes in your own language,
focused on English that earns money** (job interviews, serving customers, tourists, phone calls,
selling).

The learner speaks. The on-device speech recognition turns it into text. Mwalimu (the AI tutor)
answers in simple English, corrects up to three real mistakes, explains each one in Swahili (or
Hausa, Hindi and so on), scores the sentence and keeps the conversation going. Weekly lessons set
up each role-play.

Why this and not another idea:

| Evidence | What it means |
|---|---|
| About 1.5–1.75 billion people are learning or using English as a non-native language ([EC English](https://ecenglish.com/en/blog/news/70-statistics-about-the-english-language/), [British Council](https://www.britishcouncil.cn/en/EnglishGreat/numbers)) | One of the largest consumer education markets there is |
| Language-learning apps earned $1.54B in 2025 ([Business of Apps](https://www.businessofapps.com/data/language-learning-app-market/)) | People already pay for this on their phones |
| Speak, an AI speaking-practice app, passed $100M revenue at a $1B valuation ([LinkedIn/Forbes](https://www.linkedin.com/posts/rashishrivastava98_how-ai-language-learning-app-speak-is-taking-activity-7394440610465792000-ubIa)). ELSA has 25M+ users ([Capterra](https://www.capterra.com/p/240698/ELSA-Speak/)). Praktika charges about $8 a month ([Praktika](https://intercom.help/praktika-ai/en/articles/11684862-what-subscription-plans-does-praktika-offer-and-what-is-included-in-the-paid-plan)) | Speaking practice specifically is proven demand |
| The big apps explain in English or a handful of big languages, at prices set for rich markets | Hundreds of millions of learners in Swahili, Hausa, Amharic and similar markets are under-served at local prices |
| You already have a brand (masomo.co.tz), a Swahili audience, a price people have paid (TSh 2,000 a week) and the on-device speech pieces in the app | You start ahead of anyone copying this |

Ideas I rejected: marketplaces (you need both sides at once), generic "ChatGPT wrapper" apps (no
distribution and no moat), and B2B SaaS (long sales cycles for a solo founder). Each was a weaker
fit for your assets.

---

## 2. Target customers

**Primary (launch): Swahili speakers aged 18–35 in Tanzania and Kenya who understand some English
but freeze when they have to speak it.** More than 200M people speak Swahili ([Wikipedia](https://en.wikipedia.org/wiki/Swahili)).
Tanzania alone had 58.6M internet subscriptions in Dec 2025, and smartphone penetration was around
42% and rising ([The Citizen](https://www.thecitizen.co.tz/tanzania/business/tanzania-s-digital-economy-on-track-as-internet-penetration-soars-to-85pc-5339568),
[TechAfrica](https://techafricanews.com/2025/10/20/tanzania-records-56-3-million-internet-users-as-connectivity-reaches-87-of-population/)).

| Persona | Pain | What they pay for |
|---|---|---|
| Graduate or job seeker | Interviews in English; loses jobs to "better English" | Job-interview role-plays (weeks 9–10) |
| Hotel, tour and restaurant worker (Zanzibar, Arusha, Mombasa) | Tourists; tips and promotion depend on English | Tourism and customer scenarios (weeks 3–8) |
| Small trader or online seller | Foreign buyers, Instagram/WhatsApp selling | "Sell your product" scenario (week 11) |
| Worker heading abroad (Gulf, Europe) | Needs survival and work English quickly | Daily speaking habit, phone calls |
| Secondary school leaver or university student | Classes in English, fear of speaking | Free talk, confidence |

**Secondary (after month 3): B2B seats.** Tuition centres, private schools, hotels and tour
companies buy seats for staff or students. Suggested price: TSh 5,000 per seat per month, minimum
20 seats. A 20-seat client pays TSh 100,000 a month, about as much as 12 weekly subscribers.

**Later markets (Section 7):** Nigeria and Ghana (Hausa, Yoruba), Ethiopia (Amharic), francophone
Africa (French), Mozambique and Angola (Portuguese), South Asia (Hindi, Bengali, Urdu), and
Indonesia and Vietnam. The tutor already supports these native languages through one setting.

---

## 3. What they will pay

| Plan | Price | Net to you after fees | Net per 30 days | Where |
|---|---|---|---|---|
| Free | 0: 10 AI conversation turns a day + week-1 lessons | – | – | All |
| **Weekly (main plan)** | **TSh 2,000** (~$0.76) | ~$0.74 | **$3.15** | Mobile money (TZ) |
| Monthly | TSh 7,000 (~$2.65) | ~$2.57 | $2.57 | Mobile money (TZ) |
| Quarterly | TSh 18,000 (~$6.82) | ~$6.61 | $2.20 | Mobile money (TZ) |
| Pro Monthly | $4.99 US list; set lower regional prices in Play Console | ~$4.24 | $4.24 | Google Play (global) |
| Pro Yearly | $29.99 US list | ~$25.49 | $2.10 | Google Play (global) |

Why these prices:
- TSh 2,000 a week is **your existing price**, so it has already been tested with real customers.
  Weekly plans fit how people spend money on mobile money. Education apps have the highest weekly
  renewal rate of any category, 58% ([RevenueCat](https://www.revenuecat.com/state-of-subscription-apps-2025)).
- Globally, the median education subscription is $12.99 a month and $44.99 a year
  ([Airbridge](https://www.airbridge.io/en/blog/subscription-app-pricing-by-category-2026-benchmark),
  [RevenueCat](https://www.revenuecat.com/state-of-subscription-apps-2025)), and Praktika is about
  $8 a month. A $4.99 list price undercuts all of them while clearing costs comfortably.
- Fees: Google Play takes 15% on subscriptions. Mobile-money aggregators charge about 2–3.5%; I
  assumed 3%, so negotiate. All prices live in one file (`jarvis/jarvis/plans.py`).

**AI cost check.** Each tutor turn costs about $0.0025 (Claude Haiku 4.5 at $1/$5 per million
tokens, about 1.4k tokens in and 200 out, text only; speech is handled on the device). A paid user
doing 15 turns a day on 20 days a month costs about **$0.75 a month**, roughly 25–30% of TZ
revenue. Daily turn limits cap the worst case, and the Analyst agent reports real gross margin
every day. If AI cost goes above 35% of revenue, switch `JARVIS_TUTOR_MODEL` to a cheaper model;
it is a one-line change.

---

## 4. What you need for production

### 4a. Business and legal (weeks 1–3)
| Item | Why | Rough cost |
|---|---|---|
| Registered business (BRELA) + TIN | A payment aggregator merchant account needs it | Local fees |
| **PDPC registration as a data controller** | Mandatory in Tanzania for anyone collecting personal data ([PDPC](https://www.pdpc.go.tz/en/registration-data-controller-processor/)). The app records voice | Local fees |
| Privacy policy + terms (Swahili and English) | Play Store and PDPC | Template + review |
| AzamPay merchant account (alternatives: Selcom, ClickPesa) | One API for M-Pesa, Mixx/Tigo, Airtel, HaloPesa ([comparison](https://www.mctaba.com/learn/tanzania/selcom-vs-clickpesa-vs-pesapal-vs-direct-api-tanzania)) | % per transaction |
| Google Play developer account + payments profile | Global billing. Tanzania developers can sell ([Android Police](https://www.androidpolice.com/2018/03/09/developers-ecuador-can-now-sell-paid-apps-play-store/)) | $25 one-time |
| Anthropic API account with a monthly spend limit | Tutor + back-office agents | Usage-based |

### 4b. App (Flutter): must fix before launch
1. **Migrate to current Flutter 3.x with Dart 3 null safety.** `FlatButton`, `Overflow.visible` and
   SDK `<3.0.0` no longer compile.
2. **New package ID**, for example `tz.co.masomo.app`. Play rejects `com.example.*`
   ([ref](https://teamtreehouse.com/community/couldnt-upload-apk-because-comexample-is-restricted-what)).
3. **Target API 36.** Play requires it for new apps and updates since 31 Aug 2026; extensions run
   to 1 Nov 2026 ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)).
4. Replace the Dialogflow chatbot (`lib/src/user/chatbot.dart`) with a voice screen:
   `speech_to_text` → `POST /v1/tutor/chat` → show corrections → `flutter_tts` reads the reply.
5. Replace the manual payment screen (`lib/src/user/fanyaMalipo.dart`) with plan picker →
   `POST /v1/pay/mobile` → "enter your PIN" → poll `/v1/pay/status`. Add Google Play Billing for
   users outside Tanzania.
6. Remove the hardcoded `'masomo'` password (`lib/src/user/homepage.dart:131`) and the personal
   phone numbers. Use the bearer token from `/v1/users`, with SMS OTP.
7. Remove the committed `build/` folder (10,487 generated files) from git.
8. Add a paywall screen for the 429/402 responses, and analytics events (install, first
   conversation, paywall view, purchase).

### 4c. Backend: done in this repo (`jarvis/`)
API server, tutor, lessons, payments (AzamPay + Google Play), support, analytics, 15 passing
tests, Dockerfile. Hosting: a $6–12/month VPS. Full list in [`jarvis/README.md`](../jarvis/README.md).

### 4d. Content and marketing kit
- 12-week "English for work" curriculum. The Lesson agent writes it; you review each week before
  it goes live. Your existing videos can stay as extra material.
- A phone, a $15 ring light and a lapel mic. One person films 2 short videos a day from the
  Growth agent's scripts.
- Channels: TikTok, Instagram Reels, YouTube Shorts, a WhatsApp Channel, and a Facebook page for
  older users.
- Paid test budget: **$150–300 a month** on Meta and TikTok app-install ads, only after organic
  videos show which hooks work.

### 4e. Monthly running cost at $1,000 MRR (estimate)
| Item | $/month |
|---|---|
| VPS + backups + domain | ~15 |
| AI (≈330 paid × $0.75 + free users) | ~300 |
| Ads | 150–300 |
| Store and payment fees | already deducted in the net prices above |
| **Total** | **~$465–615 → ~$385–535 a month left for you** |

---

## 5. How many customers or transactions for $1,000 MRR

| Customer mix | Net / sub / month | **Paying subs needed** | Payments / month |
|---|---|---|---|
| All TZ monthly (TSh 7,000) | $2.57 | **389** | 389 |
| All TZ weekly (TSh 2,000) | $3.15 | **318** | ~1,375 (4.33 per sub) |
| All Google Play monthly ($4.99) | $4.24 | **236** | 236 |
| **Realistic blend: 50% weekly, 20% monthly, 30% Play** | ~$3.36 | **≈300** | ~800 |
| Blend + one 40-seat B2B client (TSh 200k ≈ $73) | – | **≈280 consumers + 1 client** | – |

**Funnel to hold about 300 paying subscribers:**

Steady state: paying subscribers = new payers per month ÷ monthly churn. With 25–30% monthly churn
(normal for weekly plans), you need about **75–90 new payers a month**.

| Scenario | Install → paid within 30 days | Installs needed / month |
|---|---|---|
| Conservative (freemium median ~2%, [RevenueCat](https://www.revenuecat.com/state-of-subscription-apps-2025)) | 2% | ~4,500 |
| Base (good onboarding + a limit-hit paywall) | 4% | ~2,250 |
| Good (a 3-day trial paywall; hard paywalls convert ~5× better) | 8% | ~1,100 |

2,000–4,500 installs a month in a Swahili niche is realistic from daily short videos plus a small
ad test. Expect **3–6 months** from launch to $1,000 MRR in the base case. That estimate is not
a guarantee; the Analyst agent tells you each day which funnel step is the bottleneck.

---

## 6. Why people will actually buy

- **A painful, specific problem:** freezing when speaking English. It costs people jobs, tips and
  sales.
- **Clear value at a price they already pay:** 40 practice conversations a day for TSh 2,000 a
  week. A human tutor costs many times that for one hour.
- **No shame:** practising with an AI removes the fear of being laughed at, which is the main
  reason learners avoid speaking.
- **Local:** explanations in their own language, local names and jobs in the lessons, and payment
  by M-Pesa PIN prompt.
- **Proof:** Speak, ELSA and Praktika show people pay for AI speaking practice. You are bringing it
  to a market they don't serve at local prices.

**Test it before scaling.** Launch to your existing Masomo users and WhatsApp contacts. You want at
least **30 paying users in the first 30 days**. If fewer than 2% of active users pay, fix
onboarding and the paywall before spending anything on ads.

---

## 7. Going global, step by step

The code is global-ready now: 15 native languages (`jarvis/jarvis/agents/__init__.py`), Google
Play billing, and a lesson factory that writes packs per language (`--lang ha`).

**Rule: open a new market only when the current one shows** day-30 retention ≥ 15%, active → paid
≥ 3%, AI cost ≤ 35% of revenue, and support tickets under 2% of payers.

| Phase | Market | Explain-language | Payment |
|---|---|---|---|
| 1 (months 1–4) | Tanzania, then Kenya | Swahili | AzamPay (TZ); Play (KE). Add M-Pesa Kenya via Daraja/Paystack later |
| 2 | Nigeria, Ghana | Hausa, Yoruba, English-based coaching | Play; Paystack/Flutterwave later |
| 3 | Ethiopia, francophone Africa, Mozambique/Angola | Amharic, French, Portuguese | Play |
| 4 | Bangladesh, Pakistan, India, Indonesia, Vietnam | Bengali, Urdu, Hindi, Indonesian, Vietnamese | Play with regional pricing |

Each new market costs one lesson run, one marketing brief (`jarvis growth --lang ha --market
"Northern Nigeria"`), one creator filming locally, and Play regional prices.

---

## 8. The JARVIS agents (built and tested)

| Agent | Does | How |
|---|---|---|
| **Mwalimu (tutor)** | The product: role-plays in 6 scenarios, corrections, explanations in the learner's language, CEFR level tracking, daily limits | `POST /v1/tutor/chat` |
| **Lesson factory** | Writes a full week: vocabulary, phrases, dialogue, grammar, speaking tasks, quiz (answers validated) | `python -m jarvis lessons --weeks 1-12 --lang sw` |
| **Growth** | Daily short-video scripts, WhatsApp posts and ad variants as Markdown + CSV | `python -m jarvis growth --days 7` |
| **Support** | Answers customers from real account and payment data; escalates money problems to you | `POST /v1/support`, `python -m jarvis support "…"` |
| **Analyst** | MRR, churn, conversion, AI cost, margin, subscribers still needed for $1,000, and next week's actions | `python -m jarvis report --advice` |
| **Daily routine** | Report + next lesson + tomorrow's posts + open tickets, run by cron at 05:00 EAT | `python -m jarvis daily` |
| **Payments** | AzamPay mobile-money checkout + callback (idempotent, amount-checked, secret-protected); Google Play verify + acknowledge | `/v1/pay/*` |

What stays human: filming and posting, reading lessons before they go live, refunds and escalated
tickets, and pricing decisions.

---

## 9. 90-day roadmap

| Weeks | Deliverable | Done when |
|---|---|---|
| 1–2 | Company + PDPC + AzamPay sandbox; deploy JARVIS API; generate and review lessons 1–4 | Sandbox payment turns Pro on |
| 2–5 | Flutter migration, new package ID, API 36, voice tutor screen, new payment screen, paywall, remove security issues | Internal test build on Play |
| 4–5 | Start posting 2 videos a day (Growth agent) to build an audience **before** launch; start a WhatsApp Channel | 1,000 followers / 300 waitlist |
| 6 | Launch in Tanzania: existing users + waitlist + Play closed → open testing | First 30 paying |
| 7–9 | Improve the funnel from the daily report: onboarding, paywall copy, trial test; first $50–100 ad test | Active → paid ≥ 3% |
| 9–12 | Kenya via Play; pitch 5 tuition centres / hotels for B2B seats; lessons 5–12 | ~150 paying, 1 B2B client |
| 13–24 | Scale what works; decide on phase-2 market using the rule in Section 7 | **~300 paying ≈ $1,000 MRR** |

**Weekly KPIs** (from `jarvis report`): installs, day-1 and day-7 retention, conversations per
active user, paywall views → purchases, MRR, churn, AI cost %, and open tickets.

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| AI costs rise faster than revenue | Daily limits, cost tracked per turn, model switch is one setting, margin alarm at 35% |
| Low willingness to pay | Keep the proven TSh 2,000/week price; weekly plans; B2B seats; validate with 30 payers before spending on ads |
| Payment fraud / "I paid" disputes | Automated PIN-prompt checkout, amount matching, idempotent callbacks, human queue |
| Big apps add Swahili | Stay niche: work-English scenarios, local content, local payment, and your creator brand |
| Speech recognition struggles with accents | The tutor prompt ignores punctuation and ASR noise; offer typing as a fallback; the app's on-device STT supports the `en-TZ`/`en-KE` locales where available |
| Regulation (data, content) | PDPC registration, privacy policy, no voice audio stored on the server (text only) |
| Founder time | The agents do lessons, scripts, support and reporting; you spend your time on filming and product |

---

## 11. Questions only you can answer

1. Is the masomo.co.tz backend still live, and how many users and payers has it had? Real
   historical numbers would replace my conversion assumptions.
2. Do you already have a registered company and TIN? That decides how fast AzamPay goes live.
3. Is the old app on Google Play under a different package ID? If yes, we update that listing
   instead of starting a new one.
4. Who will be on camera for the short videos? Distribution is the part the agents can't do for
   you.

### Sources
[Business of Apps](https://www.businessofapps.com/data/language-learning-app-market/) ·
[EC English](https://ecenglish.com/en/blog/news/70-statistics-about-the-english-language/) ·
[British Council](https://www.britishcouncil.cn/en/EnglishGreat/numbers) ·
[Capterra: ELSA](https://www.capterra.com/p/240698/ELSA-Speak/) ·
[Speak $100M revenue](https://www.linkedin.com/posts/rashishrivastava98_how-ai-language-learning-app-speak-is-taking-activity-7394440610465792000-ubIa) ·
[Praktika plans](https://intercom.help/praktika-ai/en/articles/11684862-what-subscription-plans-does-praktika-offer-and-what-is-included-in-the-paid-plan) ·
[RevenueCat State of Subscription Apps 2025](https://www.revenuecat.com/state-of-subscription-apps-2025) ·
[Airbridge pricing benchmarks](https://www.airbridge.io/en/blog/subscription-app-pricing-by-category-2026-benchmark) ·
[Anthropic Haiku pricing](https://www.anthropic.com/claude/haiku) ·
[OpenAI Realtime pricing (voice alternative)](https://www.eesel.ai/blog/gpt-realtime-mini-pricing) ·
[DataReportal Tanzania](https://datareportal.com/reports/digital-2025-tanzania) ·
[The Citizen: TZ internet](https://www.thecitizen.co.tz/tanzania/business/tanzania-s-digital-economy-on-track-as-internet-penetration-soars-to-85pc-5339568) ·
[Swahili](https://en.wikipedia.org/wiki/Swahili) ·
[TZ payment aggregators](https://www.mctaba.com/learn/tanzania/selcom-vs-clickpesa-vs-pesapal-vs-direct-api-tanzania) ·
[AzamPay Go SDK](https://pkg.go.dev/github.com/Golang-Tanzania/azampay) ·
[PDPC registration](https://www.pdpc.go.tz/en/registration-data-controller-processor/) ·
[Play target API](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) ·
[Play merchants in Tanzania](https://www.androidpolice.com/2018/03/09/developers-ecuador-can-now-sell-paid-apps-play-store/) ·
[Wise TZS/USD](https://wise.com/gb/currency-converter/tzs-to-usd-rate/history)
