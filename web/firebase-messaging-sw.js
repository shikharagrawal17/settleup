importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyDZ3TynJGflB0ek11ytLmtWvDC9JtwIbTY",
  authDomain: "test-732f2.firebaseapp.com",
  projectId: "test-732f2",
  storageBucket: "test-732f2.firebasestorage.app",
  messagingSenderId: "455221731717",
  appId: "1:455221731717:web:0f5fdbf36d074237f364ec"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/favicon.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
