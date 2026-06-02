const nodemailer = require("nodemailer");
const { Resend } = require("resend");

function buildOtpEmail({ otp, username }) {
  const safeUsername = username || "there";

  return {
    subject: "Verify your MindCare account",
    text: `Hi ${safeUsername},

Your MindCare verification OTP is: ${otp}

This OTP will expire in 10 minutes.

If you did not request this, please ignore this email.`,
    html: `
      <div style="font-family:Arial,sans-serif;line-height:1.5">
        <h2>Verify your MindCare account</h2>
        <p>Hi ${safeUsername},</p>
        <p>Your verification OTP is:</p>
        <h1 style="letter-spacing:4px">${otp}</h1>
        <p>This OTP will expire in <b>10 minutes</b>.</p>
        <p>If you did not request this, please ignore this email.</p>
      </div>
    `,
  };
}

function createSmtpTransporter() {
  const host = process.env.SMTP_HOST;
  const port = Number(process.env.SMTP_PORT || 587);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;

  if (!host || !user || !pass) {
    throw new Error("SMTP email configuration is missing");
  }

  return nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
    family: 4,
    connectionTimeout: 15000,
    greetingTimeout: 10000,
    socketTimeout: 20000,
  });
}

async function sendVerificationOtpEmail({ to, otp, username }) {
  const from =
    process.env.SMTP_FROM ||
    process.env.EMAIL_FROM ||
    process.env.SMTP_USER ||
    "MindCare <no-reply@mindcare.app>";

  const email = buildOtpEmail({ otp, username });

  if ((process.env.EMAIL_PROVIDER || "").toLowerCase() === "resend") {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) {
      throw new Error("RESEND_API_KEY is missing");
    }

    const resend = new Resend(apiKey);

    const { data, error } = await resend.emails.send({
      from,
      to,
      subject: email.subject,
      text: email.text,
      html: email.html,
    });

    if (error) {
      throw new Error(
        `Resend email failed: ${error.message || JSON.stringify(error)}`,
      );
    }

    return data;
  }

  const transporter = createSmtpTransporter();

  await transporter.sendMail({
    from,
    to,
    subject: email.subject,
    text: email.text,
    html: email.html,
  });
}

module.exports = {
  sendVerificationOtpEmail,
};