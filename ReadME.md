# Neuro-Transmitter

[**View on the iOS App Store**](https://apps.apple.com/us/app/neuro-transmitter/id6463495879)

Neuro-Transmitter is a native iOS application designed to provide secure, gated access to specialized resources. Built with SwiftUI and Firebase, the platform enforces a strict identity management protocol where user access requires explicit administrator verification, ensuring sensitive information remains protected.

## Project Overview

The primary goal of this application was to implement a secure "invite-only" style architecture. Unlike standard apps where sign-up grants immediate access, Neuro-Transmitter introduces a verification layer. New users can register an account, but they remain in a restricted "pending" state until an administrator manually validates their credentials in the backend.

## Key Features

* **Gated Authentication System:** Users can securely sign up via email and password, but login capabilities are restricted until the account status is updated by an admin.
* **Real-Time Push Notifications:** Integrated Firebase Cloud Messaging to deliver instant alerts and updates to approved users.
* **Cloud Data Storage:** Utilizes Firestore for secure, scalable user data management and retrieval.
* **Adaptive User Interface:** Fully supports system-wide Dark Mode and Light Mode, ensuring a consistent experience across all iOS device sizes (iPhone and iPad).

## Technical Architecture

The application leverages a modern serverless architecture:

* **Frontend:** Swift & SwiftUI
* **Backend:** Firebase (Firestore, Authentication, Cloud Messaging)
* **Security:** Role-based access control logic implemented via Firestore security rules.

## How It Works

The authentication flow follows a strict security model:

1.  **Registration:** A user downloads the app and registers with their name, email, and password.
2.  **Pending State:** Immediately after registration, the user is placed in a "holding" queue. If they attempt to log in, they receive a system message: *"Thank you for creating an account, please contact admin for approval before sign in."*
3.  **Admin Verification:** The administrator reviews the new account in the backend console and toggles the user's status to "Approved."
4.  **Access Granted:** Once approved, the user gains full access to the application resources and begins receiving push notifications.

## Future Roadmap

* **Web Admin Dashboard:** Developing a React-based web interface to allow administrators to approve/deny users without accessing the database console directly.
* **User Analytics:** implementing tracking to monitor engagement and resource usage.
* **Theming Engine:** Adding support for custom color schemes beyond the system defaults.

## Installation and Setup

To run this project locally:

1.  **Clone the repository**
    ```bash
    git clone [https://github.com/zayeemZaki/NeuroTransmitter.gir](https://github.com/zayeemZaki/NeuroTransmitter)
    ```

2.  **Open in Xcode**
    Navigate to the project folder and open the `.xcodeproj` file.

3.  **Configure Firebase**
    * Add your own `GoogleService-Info.plist` file to the root directory.
    * Ensure the Bundle ID matches your Firebase console settings.

4.  **Build and Run**
    Select your target simulator (iPhone 15/16 recommended) and press `Cmd + R`.

## Gallery

![Pic 1](https://github.com/zayeemZaki/NeuroTransmitter/blob/NeuroTransmitter/gallery/Neu1.jpeg)

![Pic 2](https://github.com/zayeemZaki/NeuroTransmitter/blob/NeuroTransmitter/gallery/neu2.jpeg)

![Pic 3](https://github.com/zayeemZaki/NeuroTransmitter/blob/NeuroTransmitter/gallery/neu3.jpeg)
