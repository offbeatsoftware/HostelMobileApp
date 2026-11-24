// =====================================================================
// Shri Balaji Hostel: the "send-email" Edge Function.
//
// The phone calls it to send invoices, receipts, fee reminders and
// attendance emails through the hostel's Gmail account, as the desktop
// program does. It also saves the Gmail app password (in Supabase Vault,
// encrypted) and sends the test email.
//
// Deploy (see the README): Supabase Dashboard > Edge Functions > Deploy a
// new function > paste this file, name it  send-email , and turn OFF
// "Verify JWT" (the function checks the signed in admin itself, below,
// because the app signs in with Firebase).
//
// Security: only the signed in hostel admin (public.is_hostel_admin(), from
// script 002) may use it. The password is never returned to the phone.
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// ---- helpers (no network; checked by the tests in the repository) ----
// BEGIN HELPERS

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024;

interface Attachment {
  name: string;
  base64: string;
}

interface LogInfo {
  emailType: string;
  studentId: number;
  invoiceIds?: number[];
  // An absence email: the night it was about.
  attendanceDate?: string;
}

interface SendRequest {
  action: string;
  to?: string;
  toName?: string;
  cc?: string;
  subject?: string;
  body?: string;
  attachments?: Attachment[];
  log?: LogInfo;
  password?: string;
}

/** Gmail shows the app password in groups of four; the spaces are not part of it. */
function cleanPassword(text: string | undefined): string {
  return (text ?? "").replace(/\s+/g, "");
}

/** The message to show when a request is wrong, or null when it is fine. */
function checkSend(r: SendRequest): string | null {
  if (!r.to || !EMAIL_PATTERN.test(r.to.trim())) {
    return "An email address is not valid. Check the sender and the parent's email address.";
  }
  if (r.cc && r.cc.trim() !== "" && !EMAIL_PATTERN.test(r.cc.trim())) {
    return "An email address is not valid. Check the sender and the parent's email address.";
  }
  if (!r.subject || r.subject.trim() === "" || !r.body || r.body.trim() === "") {
    return "The email needs a subject and a message.";
  }
  if (r.subject.length > 255) return "The subject is too long.";
  let bytes = 0;
  for (const a of r.attachments ?? []) {
    if (!a.name || !a.base64) return "An attachment is empty.";
    bytes += Math.floor((a.base64.length * 3) / 4);
  }
  if (bytes > MAX_ATTACHMENT_BYTES) {
    return "The attachments are larger than 8 MB.";
  }
  return null;
}

/** Turns an SMTP failure into a message the admin can act on, as the desktop does. */
function friendlyError(host: string, error: unknown): string {
  const details = `${error instanceof Error ? error.message : error}`;
  if (/535|5\.7\.0|5\.7\.8|auth|credential|password/i.test(details)) {
    return "Gmail did not accept the sender address and app password. Check them in Email Settings " +
      "(use a Gmail app password, not the normal password).";
  }
  if (/timed? ?out|connect|ECONN|ENOTFOUND|network|dns|refused|broken pipe|eof/i.test(details)) {
    return `Could not connect to ${host}. Check the internet connection and try again.`;
  }
  return "The email could not be sent. The technical details are in the function's logs.";
}

/**
 * Supabase blocks the outgoing SMTP ports 25 and 587, so Gmail is reached on
 * port 465 (encrypted from the start) instead, the same account and password.
 */
function connectionPort(port: number): number {
  return port === 587 || port === 25 ? 465 : port;
}

// END HELPERS

function reply(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function logEmail(
  admin: ReturnType<typeof createClient>,
  r: SendRequest,
  error: string | null,
) {
  const log = r.log;
  if (!log) return;
  if (error === null && log.attendanceDate) {
    await admin
      .from("attendance")
      .update({ parent_emailed_date: new Date().toISOString() })
      .eq("student_id", log.studentId)
      .eq("attendance_date", log.attendanceDate);
  }
  const ids = log.invoiceIds && log.invoiceIds.length > 0 ? log.invoiceIds : [null];
  await admin.from("email_history").insert(
    ids.map((invoiceId) => ({
      student_id: log.studentId,
      invoice_id: invoiceId,
      recipient_email: r.to,
      email_type: log.emailType,
      subject: (r.subject ?? "").slice(0, 255),
      status: error === null ? "Sent" : "Failed",
      error_message: error === null ? null : error.slice(0, 255),
    })),
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ ok: false, error: "Use POST." }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const authorization = req.headers.get("Authorization") ?? "";

  // Only the signed in hostel admin.
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: isAdmin, error: authError } = await caller.rpc("is_hostel_admin");
  if (authError || isAdmin !== true) {
    return reply({ ok: false, error: "Only the hostel admin can send emails." }, 403);
  }

  let r: SendRequest;
  try {
    r = await req.json();
  } catch {
    return reply({ ok: false, error: "The request could not be read." }, 400);
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // ---- Save the Gmail app password (Vault) ----
  if (r.action === "save_password") {
    const password = cleanPassword(r.password);
    if (password === "") {
      return reply({ ok: false, error: "Please enter the Gmail app password." });
    }
    const { error } = await admin.rpc("_set_gmail_app_password", { p_password: password });
    if (error) {
      return reply({ ok: false, error: "The app password could not be saved. Run supabase/015_email_sending.sql first." });
    }
    return reply({ ok: true });
  }

  if (r.action !== "send" && r.action !== "test") {
    return reply({ ok: false, error: "Unknown action." }, 400);
  }

  // ---- The Gmail account ----
  const { data: rows } = await admin
    .from("app_setting")
    .select("setting_key, setting_value")
    .in("setting_key", ["Email.SmtpHost", "Email.SmtpPort", "Email.SenderEmail", "Email.SenderName"]);
  const setting = (key: string, fallback: string) => {
    const v = rows?.find((x) => x.setting_key === key)?.setting_value;
    return v && v.trim() !== "" ? v.trim() : fallback;
  };
  const host = setting("Email.SmtpHost", "smtp.gmail.com");
  const configuredPort = Number(setting("Email.SmtpPort", "587"));
  const senderEmail = setting("Email.SenderEmail", "shribalajihostelsuddhowala@gmail.com");
  const senderName = setting("Email.SenderName", "Shri Balaji Hostel");

  const { data: password } = await admin.rpc("_get_gmail_app_password");
  if (!password) {
    return reply({
      ok: false,
      error: "The Gmail app password has not been entered yet. Enter it in Email Settings on the phone first.",
    });
  }

  let to = r.to;
  let toName = r.toName;
  let subject = r.subject;
  let body = r.body;
  let attachments = r.attachments ?? [];
  if (r.action === "test") {
    to = (r.to ?? "").trim() === "" ? senderEmail : r.to!.trim();
    toName = (r.to ?? "").trim() === "" ? senderName : "";
    subject = "Test email from the Hostel Management System";
    body = `This test email shows that Shri Balaji Hostel can send invoices, receipts, fee reminders and attendance emails from ${senderEmail}.`;
    attachments = [];
  } else {
    const problem = checkSend(r);
    if (problem) return reply({ ok: false, error: problem });
  }

  // ---- Send ----
  const client = new SMTPClient({
    connection: {
      hostname: host,
      port: connectionPort(configuredPort),
      tls: true,
      auth: { username: senderEmail, password },
    },
  });
  let error: string | null = null;
  try {
    await client.send({
      from: `${senderName} <${senderEmail}>`,
      to: toName ? `${toName} <${to}>` : to!,
      cc: r.action === "send" && r.cc && r.cc.trim() !== "" ? r.cc.trim() : undefined,
      subject: subject!,
      content: body!,
      attachments: attachments.map((a) => ({
        filename: a.name,
        content: a.base64,
        encoding: "base64",
        contentType: "application/pdf",
      })),
    });
  } catch (e) {
    console.error("Sending the email failed:", e);
    error = friendlyError(host, e);
  } finally {
    try {
      await client.close();
    } catch {
      // Already closed.
    }
  }

  // A test is not logged.
  if (r.action === "send") {
    try {
      await logEmail(admin, r, error);
    } catch (e) {
      console.error("The email history could not be written:", e);
    }
  }
  return error === null ? reply({ ok: true }) : reply({ ok: false, error });
});
