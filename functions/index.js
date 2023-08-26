/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendNotificationOnNewMessage = functions.firestore
    .document('messages/{messageId}')
    .onCreate((snapshot, context) => {
        const message = snapshot.data();

        // Define notification payload
        const payload = {
            notification: {
                title: 'New Message',
                body: message.content // Assuming 'content' is a field in your message
            },
            topic: "allUsers" // Sending notification to the 'allUsers' topic
        };

        // Send a message to devices subscribed to the 'allUsers' topic
        return admin.messaging().send(payload)
            .then(response => {
                console.log('Successfully sent message:', response);
                return null;
            })
            .catch(error => {
                console.error('Error sending message:', error);
            });
    });
