# Forgot-password email (all users)

When **any** user taps **Forgot password?**, the API emails a 6-digit code **to the address they typed**. One mailbox is the **sender**; every user is a **recipient**.

**Yes — Gmail sending is free.** Google Sign-In is not mail. Gmail SMTP (port 587) is free but **your ISP blocks it** (`Network is unreachable`). Direct SMTP will not work on this Wi‑Fi. Use the **Apps Script** path below (still free Gmail, HTTPS, any recipient, ~100 emails/day).

---

## 0. Free Gmail that works on this network (do this)

1. Open [https://script.google.com](https://script.google.com) while signed into the **Gmail that will send** the codes.
2. **New project**. Delete the stub. Paste `backend/scripts/gmail_webapp.gs`.
3. Pick a long random secret (any string). Put it in **two** places:
   - `var SECRET = "...";` in the script
   - `GMAIL_WEBAPP_SECRET=...` in `.env`
4. **Deploy → New deployment → Web app**
   - Execute as: **Me**
   - Who has access: **Anyone**
5. Authorize Gmail when Google asks.
6. Copy the Web app URL into `.env`:

```
GMAIL_WEBAPP_URL=https://script.google.com/macros/s/..../exec
GMAIL_WEBAPP_SECRET=the-same-secret-as-in-the-script
```

Remove `BREVO_API_KEY` / `RESEND_API_KEY` so those are not used first.

7. **Restart the API.** Forgot password → any real inbox. From = your Gmail. Check spam.

If you change the script, **Deploy → Manage deployments → Edit → New version**.

---

## 1. Gmail SMTP (only on hotspot / VPN)

This is also free. It needs **port 587** (blocked on your current Wi‑Fi). Phone hotspot often works.

Gmail’s **normal password will not work**. Use an **App password**.

1. 2-Step Verification on the sender Gmail.
2. [App passwords](https://myaccount.google.com/apppasswords) → 16 characters.
3. `.env`:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=the-sender@gmail.com
SMTP_PASSWORD=xxxxxxxxxxxxxxxx
SMTP_FROM=the-sender@gmail.com
```

Restart the API. Do not set `GMAIL_WEBAPP_URL` if you want this path.

---

## 2. Check it

1. Tap **Forgot password?** with a **real inbox**.
2. No code on screen. Open that inbox + **Spam**. Subject: `Your Second Brain reset code`.

---

## 3. What you do **not** do

- Do not ask each user for their Gmail password.
- Do not put secrets in Flutter `--dart-define` or git.
- Google **sign-in** (`GOOGLE_CLIENT_ID`) is separate from sending mail.
- Resend free = only the Resend signup inbox. Skip it unless you own a domain.
