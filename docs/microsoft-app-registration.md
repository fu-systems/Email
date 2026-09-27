# Signing in to Outlook.com and Microsoft 365

Microsoft no longer accepts passwords from mail apps: Outlook.com stopped on 16 September 2024, and Microsoft 365 (Exchange Online) blocks password sign-in for IMAP and POP. Look In instead uses **Sign in with Microsoft** (OAuth 2.0). You sign in in your web browser, and Look In receives a token for your mailbox.

Look In connects in one of two ways, chosen under **Connect with** when you add the account (or later in **Account Settings**):

- **Microsoft Graph** (recommended): mail syncs over HTTPS with Microsoft's REST API, and sending works even where the organization turned off SMTP sign-in. Calendar and contacts will sync this way too.
- **IMAP and SMTP**: the classic mail protocols, with the sign-in token instead of a password.

Every OAuth app needs an **app registration** in Microsoft Entra ID. Look In does not ship one; you or your organization create it once, for free. After that, every Microsoft account in Look In uses it.

- **At work or school:** ask your IT administrator. They can register Look In once and give it to everyone (see [Providing the registration to users](#providing-the-registration-to-users)).
- **For a personal Outlook.com account:** you need a Microsoft Entra tenant to register apps in. A free Azure account comes with one.

## 1. Register the app

1. Open the [Microsoft Entra admin center](https://entra.microsoft.com) (or the Azure portal) and go to **Identity > Applications > App registrations > New registration**.
2. **Name:** `Look In`.
3. **Supported account types:** pick who will sign in.

   | Choose in Entra | Use for | In Look In, choose |
   |---|---|---|
   | Accounts in this organizational directory only | Your organization's Microsoft 365 mailboxes | Accounts in one organization only, with your tenant ID or domain |
   | Accounts in any organizational directory | Microsoft 365 mailboxes of several organizations | Work or school accounts (any organization) |
   | Accounts in any organizational directory and personal Microsoft accounts | Microsoft 365 and Outlook.com | Work or school, and personal Microsoft accounts |
   | Personal Microsoft accounts only | Outlook.com, Hotmail, Live | Personal Microsoft accounts only |

4. **Redirect URI:** choose the platform **Public client/native (mobile & desktop)** and enter `http://localhost`. Look In listens on a random local port; Microsoft ignores the port for `localhost`.
5. Select **Register**.

Leave **Allow public client flows** off. Look In uses the authorization code flow with PKCE, which doesn't need it, and it never uses a client secret.

## 2. Add permissions

In the registration, open **API permissions > Add a permission > Microsoft Graph > Delegated permissions** and add the permissions for the way people will connect (adding both lets everyone choose):

| Permission | Used for | Why |
|---|---|---|
| `Mail.ReadWrite` | Microsoft Graph | Read and organize mail, save drafts |
| `Mail.Send` | Microsoft Graph | Send mail |
| `User.Read` | Microsoft Graph | Show who is signed in |
| `Calendars.ReadWrite`, `Contacts.ReadWrite` | Microsoft Graph | Calendar and contacts sync (asked for now, so nobody needs to approve Look In again when it arrives) |
| `IMAP.AccessAsUser.All` | IMAP and SMTP | Read and organize mail over IMAP |
| `SMTP.Send` | IMAP and SMTP | Send mail over SMTP |
| `offline_access` | both | Stay signed in (refresh tokens) |
| `openid`, `profile`, `email` | both | Show who is signed in |

IMAP and SMTP are listed under Microsoft Graph in the portal even though their tokens are issued for Exchange (`outlook.office.com`).

### Admin consent (work and school accounts)

Many organizations don't let users approve apps themselves; Microsoft made admin approval the default for mail access in late 2025. An administrator can approve Look In for everyone:

- in the registration's **API permissions** page: **Grant admin consent for <organization>**, or
- for a registration in another tenant, by opening
  `https://login.microsoftonline.com/<tenant>/adminconsent?client_id=<application-id>`.

Look In shows this link, ready to copy, when a sign-in fails because approval is needed.

## 3. Enter the registration in Look In

Copy the **Application (client) ID** from the registration's **Overview** page. Then either:

- add the account: Look In asks for the registration the first time you select **Sign in with Microsoft**, or
- go to **File > Options > Microsoft accounts > Set Up...**.

Enter the client ID and choose the matching **Accounts that can sign in** (see the table above). For a single-organization registration, also enter the **Directory (tenant) ID** or your organization's domain.

## Providing the registration to users

Administrators and packagers can supply the registration so that users never see the setup dialog. Look In uses the first of these it finds:

1. What the user entered in **Options** (it replaces the others).
2. `~/.config/look-in/oauth.json` (per user, or `$XDG_CONFIG_HOME/look-in/oauth.json`).
3. `/etc/look-in/oauth.json` (for the whole computer).
4. A default compiled into the app:

   ```bash
   flutter build linux --release \
     --dart-define=LOOKIN_MS_CLIENT_ID=00000000-0000-0000-0000-000000000000 \
     --dart-define=LOOKIN_MS_TENANT=common
   ```

The file format is:

```json
{
  "microsoft": {
    "clientId": "00000000-0000-0000-0000-000000000000",
    "tenant": "common"
  }
}
```

`tenant` is `common`, `organizations`, `consumers`, or a tenant ID or domain.

## Mailbox settings

Microsoft Graph needs nothing more. With **IMAP and SMTP**, the sign-in only gets Look In in; the mailbox must also allow IMAP and SMTP:

- **Outlook.com:** Settings > Mail > Forwarding and IMAP: allow devices and apps to use IMAP.
- **Microsoft 365:** in the Microsoft 365 admin center, Users > Active users > (user) > Mail > **Manage email apps**: turn on **IMAP** and **Authenticated SMTP**. Your organization may also have turned off SMTP AUTH for everyone (Exchange admin center or `Set-TransportConfig -SmtpClientAuthenticationDisabled`).

## Troubleshooting

| Message | Meaning and fix |
|---|---|
| AADSTS65001, "needs admin approval" | An administrator must approve Look In (see [Admin consent](#admin-consent-work-and-school-accounts)). |
| AADSTS700016, "application was not found in the directory" | Wrong client ID, or the registration doesn't allow this kind of account. Check **Supported account types** and Look In's **Accounts that can sign in**. |
| AADSTS50011, "redirect URI does not match" | Add `http://localhost` as a **Mobile and desktop applications** redirect URI. |
| AADSTS7000218, "client_assertion or client_secret" | The redirect URI was added under **Web**. Move it to **Mobile and desktop applications**. |
| "Microsoft denied access to the mailbox" (Graph) | The registration lacks `Mail.ReadWrite` or `Mail.Send`, or they need admin consent. |
| "This mailbox can't be reached through Microsoft Graph" | The mailbox is on an on-premises Exchange server. Use **IMAP and SMTP**, or a password. |
| "Sign in with Microsoft again so Look In may use …" | You switched between Microsoft Graph and IMAP and SMTP; the existing sign-in only allows the other one. |
| "User is authenticated but not connected" | IMAP is turned off for the mailbox (see [Mailbox settings](#mailbox-settings)). |
| "5.7.139 … SmtpClientAuthentication is disabled" | Authenticated SMTP is turned off for the mailbox or the organization. |
| "Your Microsoft sign-in has expired" | The sign-in was revoked, your password changed, or it wasn't used for 90 days. Select **Sign In...** in the bar above the message list. |

## What Look In does with your sign-in

- The browser talks to Microsoft directly. Look In never sees your password or second factor.
- Look In keeps the refresh token in the system keyring (or encrypted in its data folder; see the README) and the short-lived access tokens only in memory.
- Tokens are sent only to `login.microsoftonline.com` (to refresh them) and to Microsoft Graph (`graph.microsoft.com`) or Microsoft's IMAP and SMTP servers.
- **File > Info > Remove Account** deletes the account's tokens. To revoke access everywhere, remove Look In at <https://myapps.microsoft.com> (work) or <https://account.live.com/consent/Manage> (personal).

## Switching an existing account to Microsoft Graph

Accounts added with IMAP and SMTP keep working. To move one to Microsoft Graph, open **File > Info > Account Settings**, choose **Connect with: Microsoft Graph**, select **Sign in again**, and save. Look In downloads the mailbox again through Graph; changes you made offline and haven't sent yet are dropped, so sync first.

## Checking a new registration

1. Add the account: **Sign in with Microsoft** shows "Signed in with Microsoft as …".
2. The **Test** step passes (Microsoft Graph, or IMAP and SMTP).
3. Mail arrives, and a message you send appears in Sent Items.
4. Restart Look In: the account connects without signing in again.
5. After an hour (when the access token expires), sending and receiving still work.
