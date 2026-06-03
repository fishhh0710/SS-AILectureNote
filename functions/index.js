const fs = require("fs");
const fsp = require("fs/promises");
const os = require("os");
const path = require("path");

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");
const OpenAIImport = require("openai");

const OpenAI = OpenAIImport.default || OpenAIImport;

admin.initializeApp();

const db = admin.firestore();
const bucket = admin.storage().bucket();
const region = process.env.FUNCTION_REGION || "us-central1";

const pageNotesSchema = {
  type: "object",
  properties: {
    pages: {
      type: "array",
      description: "One Markdown note for each PDF page.",
      items: {
        type: "object",
        properties: {
          page_number: {
            type: "integer",
            description: "The 1-based page number in the PDF.",
          },
          markdown: {
            type: "string",
            description: "Concise Markdown notes for this page.",
          },
        },
        required: ["page_number", "markdown"],
        additionalProperties: false,
      },
    },
  },
  required: ["pages"],
  additionalProperties: false,
};

exports.chat = functions
  .region(region)
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    if (handleCors(req, res)) return;

    try {
      const payload = requestPayload(req);
      const notes = optionalString(payload.notes);
      const transcript = optionalString(payload.transcript);
      const history = optionalString(payload.history);
      const question = requiredString(payload, "question");

      const openai = openAIClient();
      const response = await openai.chat.completions.create({
        model: process.env.OPENAI_CHAT_MODEL || process.env.OPENAI_MODEL || "gpt-4o-mini",
        messages: [
          {
            role: "user",
            content: buildChatPrompt({ notes, transcript, history, question }),
          },
        ],
        temperature: 0.7,
      });

      const answer = response.choices?.[0]?.message?.content?.trim();
      if (!answer) {
        throw new Error("OpenAI response did not include an answer.");
      }

      res.json({ answer });
    } catch (error) {
      sendError(res, error);
    }
  });

exports.generateNotesFromPdf = functions
  .region(region)
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onRequest(async (req, res) => {
    if (handleCors(req, res)) return;

    let tempPdfPath;
    let jobRef;

    try {
      const payload = requestPayload(req);
      const storageId = requiredString(payload, "storageId");
      const pdfStoragePath = requiredString(payload, "pdfStoragePath");
      const safeId = safeStorageId(storageId);
      const jobPath = optionalString(payload.jobPath) || `ai_note_jobs/${safeId}`;

      jobRef = jobDocument(jobPath, safeId);
      await jobRef.set(
        {
          status: "running",
          pdfStoragePath,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tempPdfPath = path.join(os.tmpdir(), `${safeId}-${Date.now()}.pdf`);
      await bucket.file(pdfStoragePath).download({ destination: tempPdfPath });

      const notes = await generatePageNotes(tempPdfPath);
      const notesStoragePath = `ai_note_jobs/${safeId}/notes/notes.json`;
      await bucket.file(notesStoragePath).save(
        JSON.stringify(notes, null, 2),
        {
          resumable: false,
          metadata: {
            contentType: "application/json",
            metadata: { storageId },
          },
        },
      );

      await jobRef.set(
        {
          status: "completed",
          notesStoragePath,
          pageCount: notes.pages.length,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      res.json({
        ...notes,
        status: "completed",
        jobPath: jobRef.path,
        notesStoragePath,
      });
    } catch (error) {
      if (jobRef) {
        await jobRef.set(
          {
            status: "failed",
            error: error.message || String(error),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      sendError(res, error);
    } finally {
      if (tempPdfPath) {
        await fsp.unlink(tempPdfPath).catch(() => {});
      }
    }
  });

function handleCors(req, res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "content-type");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }

  if (req.method !== "POST") {
    res.status(405).json({ message: "Only POST is supported." });
    return true;
  }

  return false;
}

function requestPayload(req) {
  const body = req.body || {};
  if (body.data && typeof body.data === "object") {
    return body.data;
  }
  return body;
}

function openAIClient() {
  const apiKey =
    process.env.OPENAI_API_KEY ||
    functions.config()?.openai?.key;

  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not configured for Firebase Functions.");
  }

  return new OpenAI({ apiKey });
}

function buildPdfNotesPrompt() {
  return `
You are an academic PDF note-taking assistant.

Task:
Read the entire PDF and generate concise Markdown notes for each page.

You must use:
- The page text
- Images, diagrams, charts, tables, formulas, arrows, and visual layout
- The spatial structure of each page

Output:
Return a JSON object with a "pages" array.
Each item must contain:
- page_number: the page number, starting from 1
- markdown: the Markdown note for that page

Markdown format for each page:

# Page <page_number>: <short inferred title>

## Main Idea
<Explain the main idea of this page in 2-4 concise sentences.>

## Key Terms
- **<term>**: <brief explanation based on this page>
- **<term>**: <brief explanation based on this page>

Rules:
- Generate one item for every page in the PDF.
- Do not skip pages.
- Focus on each page individually.
- Keep each page note concise.
- Explain only important technical terms, academic terms, formulas, methods, concepts, or abbreviations.
- Do not include obvious everyday words as key terms.
- If a page has no important technical terms, omit the "## Key Terms" section for that page.
- If a page is blank or contains almost no useful content, still create a short note saying that the page has limited content.
- Do not invent information that is not supported by the PDF.
- The markdown field should contain Markdown only.
- Do not wrap Markdown in markdown fences.
`.trim();
}

function buildChatPrompt({ notes, transcript, history, question }) {
  return `
You are an AI study assistant for a lecture-note app.

Answer the student's question using the lecture notes and transcript first.
If the provided context is insufficient, say what is missing and answer only at a high level.
Keep the answer concise, structured, and useful for studying.

AI notes:
${notes || "(none)"}

Lecture transcript:
${transcript || "(none)"}

Recent chat history:
${history || "(none)"}

Student question:
${question}
`.trim();
}

async function generatePageNotes(pdfPath) {
  const openai = openAIClient();
  const uploadedFile = await openai.files.create({
    file: fs.createReadStream(pdfPath),
    purpose: "user_data",
  });

  try {
    const response = await openai.responses.create({
      model: process.env.OPENAI_NOTE_MODEL || process.env.OPENAI_MODEL || "gpt-4o-mini",
      input: [
        {
          role: "user",
          content: [
            { type: "input_file", file_id: uploadedFile.id },
            { type: "input_text", text: buildPdfNotesPrompt() },
          ],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "pdf_page_notes",
          strict: true,
          schema: pageNotesSchema,
        },
      },
      max_output_tokens: 20000,
    });

    const rawJson = extractOutputText(response);
    const parsed = JSON.parse(rawJson);
    if (!Array.isArray(parsed.pages)) {
      throw new Error("Model output is missing pages.");
    }

    return parsed;
  } finally {
    await deleteUploadedOpenAIFile(openai, uploadedFile.id);
  }
}

async function deleteUploadedOpenAIFile(openai, fileId) {
  try {
    if (typeof openai.files?.del === "function") {
      await openai.files.del(fileId);
      return;
    }

    if (typeof openai.files?.delete === "function") {
      await openai.files.delete(fileId);
      return;
    }

    functions.logger.warn("OpenAI SDK has no file delete method.", { fileId });
  } catch (error) {
    functions.logger.warn("Failed to delete uploaded OpenAI file.", {
      fileId,
      message: error.message || String(error),
    });
  }
}

function extractOutputText(response) {
  if (typeof response.output_text === "string") {
    return response.output_text;
  }

  const output = response.output || [];
  const text = [];
  for (const item of output) {
    for (const part of item.content || []) {
      if (part.type === "output_text" && typeof part.text === "string") {
        text.push(part.text);
      }
    }
  }

  return text.join("");
}

function jobDocument(jobPath, safeId) {
  const segments = jobPath.split("/").filter(Boolean);
  if (segments.length % 2 === 0) {
    return db.doc(jobPath);
  }

  return db.collection("ai_note_jobs").doc(safeId);
}

function requiredString(payload, key) {
  const value = payload[key];
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Missing required string field: ${key}`);
  }
  return value.trim();
}

function optionalString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function safeStorageId(value) {
  return String(value).replace(/[^A-Za-z0-9_-]/g, "_");
}

function sendError(res, error) {
  functions.logger.error(error);
  res.status(500).json({
    message: error.message || String(error),
  });
}
