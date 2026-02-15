import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

initializeApp();

const db = getFirestore();
const USERS_COLLECTION = "users";
const BATCH_SIZE = 400;

async function updateAllUsers(update: FirebaseFirestore.UpdateData): Promise<number> {
  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let totalUpdated = 0;

  while (true) {
    let query = db.collection(USERS_COLLECTION).orderBy("__name__").limit(BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) {
      break;
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, update);
    }

    await batch.commit();
    totalUpdated += snap.size;
    lastDoc = snap.docs[snap.docs.length - 1];
  }

  return totalUpdated;
}

export const resetDailyLimits = onSchedule(
  { schedule: "0 0 * * *", timeZone: "UTC" },
  async () => {
    const update: FirebaseFirestore.UpdateData = {
      dailyRequestCount: 0,
      modelUsage: {},
      lastRequestDate: FieldValue.serverTimestamp()
    };
    await updateAllUsers(update);
  }
);

export const resetWeeklyLimits = onSchedule(
  { schedule: "0 0 * * 1", timeZone: "UTC" },
  async () => {
    const update: FirebaseFirestore.UpdateData = {
      weeklyModelUsage: {},
      lastWeeklyResetDate: FieldValue.serverTimestamp()
    };
    await updateAllUsers(update);
  }
);
