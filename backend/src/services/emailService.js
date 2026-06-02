const dns = require("dns");
dns.setDefaultResultOrder("ipv4first");
const nodemailer = require("nodemailer");

function createTransporter() {
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
  auth: {
    user,
    pass,
  },
  family: 4,
  connectionTimeout: 15000,
  greetingTimeout: 10000,
  socketTimeout: 20000,
});
}

async function sendVerificationOtpEmail({ to, otp, username }) {
  const transporter = createTransporter();

  const from =
    process.env.SMTP_FROM ||
    process.env.SMTP_USER ||
    "MindCare <no-reply@mindcare.app>";

  await transporter.sendMail({
    from,
    to,
    subject: "Verify your MindCare account",
    text: `Hi ${username || "there"},

Your MindCare verification OTP is: ${otp}

This OTP will expire in 10 minutes.

If you did not request this, please ignore this email.`,
    html: `
      <div style="font-family:Arial,sans-serif;line-height:1.5">
        <h2>Verify your MindCare account</h2>
        <p>Hi ${username || "there"},</p>
        <p>Your verification OTP is:</p>
        <h1 style="letter-spacing:4px">${otp}</h1>
        <p>This OTP will expire in <b>10 minutes</b>.</p>
        <p>If you did not request this, please ignore this email.</p>
      </div>
    `,
  });
}

module.exports = {
  sendVerificationOtpEmail,
};