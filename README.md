# IsKO-LATER ★
Author: Percie Louise Y. Samaniego
### *For when you're technically an Isko, but proCramming-level procrastinating.*

**BOOGSH K.O. ka later!!**

A simple to-do list app made for students who have **tasks everywhere and somehow still loves cramming**. Lab 1 gave it the task management stuff; Lab 2 adds **user accounts**, because apparently even procrastination needs to know who is procrastinating.

Built with **Flutter + Firebase** — because apparently even procrastination needs cloud support.

> **Course:** CMSC 128 · **Branch:** `act2-accounts`

---

## Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Local Setup & Installation](#local-setup--installation)
- [Authentication](#authentication)
- [Security](#security)
- [Data Model](#data-model)
- [Inspecting Accounts](#inspecting-accounts)
- [Known Limitations](#known-limitations)
- [Git Workflow](#git-workflow)

---

## Features

### Tasks (Lab 1)

The original task features are still here:

- Create, edit, complete, and soft-delete tasks (with undo)
- Priority and tag per task
- "Today" / "Upcoming" task grouping
- Calendar view with a dot marker on days that have tasks

### Accounts (Lab 2)

Lab 2 adds the account side of the app:

- **Register** with full name, email, and password
- **Log in / Log out** with confirmation dialogs
- **Persistent session** — stays logged in when the app is reopened
- **Protected screens** — signed-out users only see the login flow
- **Direct Tasks Landing** — logging in takes the user directly to the task list
- **Profile Screen** — account dashboard accessible from the bottom navigation
- **Inline Account Editing** — update the username and email directly from the profile
- **Re-authentication** — changing the email requires the current password
- **Email Verification** — waits for the verification link before completing an email change
- **Verification Handoff** — after verification, the session ends and the user is redirected to login
- **Forgot password** — sends a single-use reset link through email
- Friendly validation and error messages
- Loading spinners and disabled buttons while requests are processing

So basically, Lab 1 handles **the tasks**, while Lab 2 handles **the person using the app**.

---

## Tech Stack

| Layer | Choice |
|---|---|
| Frontend | Flutter (Dart), Material 3 |
| Backend | Firebase (serverless, no custom server) |
| Authentication | Firebase Authentication, Email/Password provider |
| Database | Cloud Firestore |
| Other packages | `firebase_core`, `firebase_auth`, `cloud_firestore`, `google_fonts`, `intl` |

### Why Firebase Auth?

Firebase handles the annoying security parts for us — password hashing, session tokens, and password reset flows.

The app **does not see, store, or log password hashes**.

Because apparently making our own authentication system from scratch was not enough suffering.

---

## Project Structure

Here's the big picture before we dive into the individual parts:

```text
lib/
├── main.dart
├── firebase_options.dart
├── models/
│   ├── task.dart
│   └── user.dart
├── services/
│   ├── auth_service.dart
│   └── firestore_service.dart
├── screens/
│   ├── auth_gate.dart
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── forgot_password_screen.dart
│   ├── profile_screen.dart
│   ├── home_screen.dart
│   ├── calendar_screen.dart
│   └── add_edit_task.dart
└── widgets/
    ├── auth_widgets.dart
    ├── app_shared.dart
    └── task_card.dart
```

The important part is that the screens don't handle everything themselves. Authentication logic stays in `auth_service.dart`, task database logic stays in `firestore_service.dart`, and the UI stays in the screens/widgets.

Keeps everything from turning into one giant file of suffering.

---

## Local Setup & Installation

### You'll need

- [Flutter SDK](https://docs.flutter.dev/get-started/install) — stable channel
- A Google account for Firebase
- [Firebase CLI](https://firebase.google.com/docs/cli)
- [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup)

Install FlutterFire CLI with:

```bash
dart pub global activate flutterfire_cli
```

### 1. Get the code

```bash
git clone <repository-url>
cd isko_later
git checkout act2-accounts
flutter pub get
```

### 2. Connect it to Firebase

Firebase configuration files contain project identifiers, so they are **not committed** to the repository.

Create your own Firebase project first, then:

1. Open the [Firebase Console](https://console.firebase.google.com) and create a project.
2. Go to **Authentication → Sign-in method** and enable **Email/Password**.
3. Go to **Firestore Database** and create a database.
4. Go to **Firestore → Rules** and paste the contents of `firestore.rules`.
5. Publish the rules.

Or deploy them through:

```bash
firebase deploy --only firestore:rules
```

Then connect the Flutter project:

```bash
firebase login
flutterfire configure
```

This creates `lib/firebase_options.dart` and the required platform configuration files locally.

### 3. Run

```bash
flutter run
```

That's it — pick a device/emulator when prompted and the app should launch.

No seed data or migrations are needed. The Firestore collections are created when the app writes to them for the first time.

---

## Authentication

All authentication logic is handled through Firebase Authentication and kept in:

```text
lib/services/auth_service.dart
```

The screens call the service instead of dealing with Firebase Auth directly.

### Register

The user provides:

- Full name
- Email
- Password
- Confirm password

Firebase creates the authentication account, while the user's profile information is stored separately in Firestore.

### Log in

The app uses Firebase's email/password authentication:

```dart
await FirebaseAuth.instance.signInWithEmailAndPassword(
  email: email.trim(),
  password: password,
);
```

After a successful login, `AuthGate` detects the authenticated user and sends them directly to the task list.

No unnecessary welcome screen. Straight to the procrastination.

### Persistent Session

The app listens to:

```dart
FirebaseAuth.authStateChanges()
```

When the app starts, Firebase checks the saved session.

- If a user exists → show the app
- If there is no user → show the login screen

This is why the user doesn't have to log in again every time the app is reopened.

Firebase also refreshes the authentication token when needed.

### Log out

When the user chooses to log out:

```dart
signOut()
```

clears the current session.

The app then returns to the login screen. A confirmation dialog is shown first so the user doesn't accidentally yeet themselves out of their account.

### Forgot Password

From the login screen, the user can tap **Forgot password?** and enter their email.

The flow is:

```text
Forgot password?
      ↓
Enter email
      ↓
Firebase
      ↓
Reset link sent
      ↓
User opens link
      ↓
New password
```

The reset link is **single-use and time-limited**, and the app never sees the new password.

The confirmation message is also kept generic so the screen doesn't reveal whether an email is registered.

### Update Email

Changing the email needs a few extra steps:

```text
Profile
   ↓
Edit email
   ↓
Enter current password
   ↓
Re-authenticate
   ↓
Verification link sent
   ↓
User opens link
   ↓
App checks verification
   ↓
Session ends
   ↓
Login with new email
```

The app checks whether the verification has been completed when the app is resumed.

Once the email is verified, the current session ends and the user is redirected to login with the new email pre-filled.

A little more work than changing a name, but that's kind of the point.

---

## Security

A few things are handled by Firebase instead of the app itself.

### Password Storage

Firebase handles password hashing on its servers.

The app:

- does not store plaintext passwords
- does not store password hashes
- does not log passwords
- does not display passwords

### Re-authentication

Changing the email requires the current password first.

This adds another check before making a sensitive account change.

### Login Errors

Invalid credentials use a generic error message instead of telling the user whether the email exists.

This prevents the login screen from accidentally leaking account information.

### Firestore Rules

Firestore rules control database access instead of relying only on the UI.

The rules are stored in:

```text
firestore.rules
```

### Configuration Files

Firebase configuration files and other secrets are kept out of the repository through `.gitignore`.

---

## Data Model

### Firebase Authentication

Firebase manages the actual login credentials:

- Email
- Password hash
- UID
- Created time
- Last sign-in time

### Firestore `users/{uid}`

Each user gets a profile document using their Firebase UID.

| Field | Type | Notes |
|---|---|---|
| `email` | string | user's current email |
| `displayName` | string | shown in the profile |
| `createdAt` | timestamp | set during registration |

### Firestore `tasks/{taskId}`

The task data from Lab 1 is still used:

- title
- due date/time
- priority
- tag
- done status
- deleted status

---

## Inspecting Accounts

If we need to check whether the authentication system is actually doing its job:

### Firebase Authentication

Go to:

**Firebase Console → Authentication → Users**

This shows:

- Identifier
- UID
- Created date
- Last sign-in date

It does **not** show the actual password.

### Firestore

Go to:

**Firebase Console → Firestore → `users`**

The profile documents should contain:

- `email`
- `displayName`
- `createdAt`

### Exporting Accounts

For demonstration purposes, Firebase CLI can export account data:

```bash
firebase auth:export accounts.json --format=json
```

The exported records contain a `passwordHash` and `salt` instead of a plaintext password.

**Don't commit this file.**

---

## Known Limitations

There are still a few things that aren't handled yet:

- Tasks are **not scoped per user**, so every signed-in account currently sees the same task list.
- Authentication is **email/password only**.
- There is no Google sign-in or multi-factor authentication yet.
- Changing the email depends on the verification link before the new email becomes active in the profile.

So yes, accounts work now, but the tasks are still basically saying:

> *"Everyone gets to see the same procrastination."*

---

## Git Workflow

The work was done on the:

```text
act2-accounts
```

branch.

Each step was committed separately using conventional commit prefixes:

- `feat`
- `fix`
- `style`
- `docs`
- `chore`

Final commit:

```text
cmsc128-Indiv-Act2
```

---

### Made for the Iskos who said:

> *"I'll do it later."*

…pero ma K-K.O LATER dahil sa burnt out.
