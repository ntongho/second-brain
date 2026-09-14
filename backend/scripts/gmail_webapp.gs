/**
 * Free Gmail sender for Second Brain reset codes.
 * Sends FROM this Google account TO any address the user typed.
 *
 * Change SENDER_NAME below (what people see instead of bntongho335).
 * Then: Deploy → Manage deployments → Edit (pencil) → Version: New version → Deploy
 *
 * If the old name still shows: Gmail → Settings → See all settings →
 * Accounts and Import → Send mail as → edit info → set the same name.
 */
var SECRET = "REPLACE_WITH_THE_SAME_SECRET_AS_GMAIL_WEBAPP_SECRET";
var SENDER_NAME = "Second Brain";

function doPost(e) {
  try {
    var p = JSON.parse(e.postData.contents);
    if (!p.secret || p.secret !== SECRET) {
      return ContentService.createTextOutput(JSON.stringify({ ok: false, error: "auth" })).setMimeType(
        ContentService.MimeType.JSON
      );
    }
    if (!p.to || !p.subject || !p.text) {
      return ContentService.createTextOutput(JSON.stringify({ ok: false, error: "fields" })).setMimeType(
        ContentService.MimeType.JSON
      );
    }
    MailApp.sendEmail({
      to: p.to,
      subject: p.subject,
      body: p.text,
      htmlBody: p.html || p.text,
      name: SENDER_NAME,
    });
    return ContentService.createTextOutput(JSON.stringify({ ok: true })).setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ ok: false, error: String(err) })).setMimeType(
      ContentService.MimeType.JSON
    );
  }
}
