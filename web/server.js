const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const dotenv = require('dotenv');
const cors = require('cors');
const { GoogleGenAI } = require('@google/genai');
let clipboardy = require('clipboardy');
if (clipboardy.default) clipboardy = clipboardy.default;

const multer = require('multer');
const fs = require('fs');
const path = require('path');

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('.'));

// Multer setup for uploads
const upload = multer({ dest: 'uploads/' });
if (!fs.existsSync('uploads')) fs.mkdirSync('uploads');

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const ai = new GoogleGenAI({
    apiKey: process.env.GEMINI_API_KEY,
});

async function callGemini(text, fileData = null) {
    const parts = [];
    if (text) parts.push({ text });
    if (fileData) parts.push(fileData);

    const res = await ai.models.generateContent({
        model: "models/gemini-3-flash-preview",
        contents: [
            {
                role: "user",
                parts: parts
            }
        ]
    });

    return res.candidates[0].content.parts[0].text;
}

// PC State Machine
const sessions = new Map(); // sessionId -> { ws, state }

const INITIAL_STATE = {
    tactileScript: null,
    currentSentenceIndex: 0,
    currentWordIndex: 0,
    speed: 1.0,
    isReading: false,
    timer: null,
    lastClipboard: ""
};

wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.on('pong', () => {
        ws.isAlive = true;
        // console.log("💓 Pong received");
    });

    ws.on('message', async (message) => {
        try {
            const data = JSON.parse(message);
            if (data.type === 'IDENTIFY') {
                sessions.set(data.sessionId, { ws, state: { ...INITIAL_STATE } });
                console.log(`Session ${data.sessionId} identified`);
            } else if (data.type === 'SIGNAL') {
                const session = Array.from(sessions.values()).find(s => s.ws === ws);
                if (session) handleSignal(session, data);
            }
        } catch (e) {
            console.error("WS Message Error:", e);
        }
    });

    ws.on('close', () => {
        // Find and clean up session
        for (const [id, session] of sessions.entries()) {
            if (session.ws === ws) {
                if (session.state.timer) clearTimeout(session.state.timer);
                sessions.delete(id);
                console.log(`Session ${id} disconnected`);
                break;
            }
        }
    });
});

// Heartbeat interval
const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
            console.log("💀 Terminating stale connection");
            return ws.terminate();
        }

        ws.isAlive = false;
        ws.ping();
    });
}, 30000);

wss.on('close', () => {
    clearInterval(interval);
});

function handleSignal(session, data) {
    const signal = data.signal;
    const { state } = session;
    console.log(`Signal received: ${signal}`);

    switch (signal) {
        case 'REPEAT':
            state.currentWordIndex = 0;
            startStreaming(session);
            break;
        case 'NEXT':
            if (state.tactileScript && state.currentSentenceIndex < state.tactileScript.sentences.length - 1) {
                state.currentSentenceIndex++;
                state.currentWordIndex = 0;
                startStreaming(session);
            }
            break;
        case 'PREVIOUS':
            if (state.currentSentenceIndex > 0) {
                state.currentSentenceIndex--;
                state.currentWordIndex = 0;
                startStreaming(session);
            }
            break;
        case 'SPEED':
            state.speed = data.value || 1.0;
            break;
    }
}

async function startStreaming(session) {
    const { ws, state } = session;
    if (state.timer) clearTimeout(state.timer);
    state.isReading = true;

    const streamNextWord = () => {
        if (!state.isReading) return;
        if (ws.readyState !== WebSocket.OPEN) {
            console.log("⚠️ WebSocket not open, cannot send");
            return;
        }

        const sentence = state.tactileScript.sentences[state.currentSentenceIndex];

        // Helper for reliable sending
        const sendSafe = (msg, label) => {
            console.log(`📤 Sending ${label}...`);
            ws.send(msg, (err) => {
                if (err) console.error(`❌ Failed to send ${label}:`, err);
                else console.log(`✅ Sent ${label}`);
            });
        };

        // If we just started a sentence, send the SET_SENTENCE for demo telemetry
        if (state.currentWordIndex === 0) {
            const msg = JSON.stringify({
                type: 'SET_SENTENCE',
                value: sentence.text
            });
            sendSafe(msg, `SET_SENTENCE (${sentence.text.substring(0, 10)}...)`);
        }

        if (state.currentWordIndex < sentence.words.length) {
            const word = sentence.words[state.currentWordIndex];
            const msg = JSON.stringify({ type: 'WORD', value: word });
            sendSafe(msg, `WORD (${word})`);

            state.currentWordIndex++;

            const baseDelay = 1200; // Increased to ensure vibration completes
            const delay = baseDelay / state.speed;
            state.timer = setTimeout(streamNextWord, delay);
        } else {
            // Sentence End
            const msg = JSON.stringify({ type: 'SENTENCE_END' });
            sendSafe(msg, "SENTENCE_END");

            // Check if there are more sentences
            if (state.currentSentenceIndex < state.tactileScript.sentences.length - 1) {
                state.currentSentenceIndex++;
                state.currentWordIndex = 0;
                // Brief pause between sentences
                state.timer = setTimeout(streamNextWord, 1000);
            } else {
                // Paragraph End (end of script)
                const msg = JSON.stringify({ type: 'PARAGRAPH_END' });
                sendSafe(msg, "PARAGRAPH_END");
                state.isReading = false;
            }
        }
    };

    streamNextWord();
}

// Clipboard Polling (Capture Mechanism)
// Clipboard Polling (Capture Mechanism)
setInterval(async () => {
    try {
        // console.log("Polling clipboard..."); // Commented out to avoid spam, uncomment if needed
        const currentText = await clipboardy.read();
        for (const [id, session] of sessions.entries()) {
            if (currentText && currentText !== session.state.lastClipboard) {
                console.log(`📋 Clipboard changed: "${currentText.substring(0, 20)}..."`);
                session.state.lastClipboard = currentText;
                console.log(`New clipboard detected: ${currentText.substring(0, 30)}...`);
                processText(currentText, id);
            }
        }
    } catch (e) {
        console.error("❌ Clipboard Polling Error:", e);
    }
}, 1000);

async function processText(text, sessionId, fileData = null) {
    const session = sessions.get(sessionId);
    if (!session) return;

    try {
        const prompt = `Simplify this content for tactile reading. Use short, simple words suitable for vibration pacing. 
        Avoid punctuation inside words. Keep sentences ≤ 10 words. Summarize aggressively. Remove filler words.
        Return ONLY a JSON object with this structure:
        {
          "sentences": [
            { "text": "Short simplified sentence", "words": ["Short", "simplified", "sentence"] }
          ]
        }
        Content to process: ${text || "See attached file"}`;

        let responseText = await callGemini(prompt, fileData);

        // Clean markdown if Gemini returns it
        responseText = responseText.replace(/```json\n?|\n?```/g, '').trim();

        const tactileScript = JSON.parse(responseText);

        session.state = {
            ...session.state,
            tactileScript,
            currentSentenceIndex: 0,
            currentWordIndex: 0
        };

        // Start streaming immediately
        startStreaming(session);

    } catch (error) {
        console.error("Processing Error:", error);
        throw error;
    }
}

app.post('/process', async (req, res) => {
    const { text } = req.body; // sessionId ignored, we broadcast
    try {
        const promises = [];
        for (const [id, session] of sessions.entries()) {
            console.log(`Broadcasting text to session: ${id}`);
            promises.push(processText(text, id));
        }
        await Promise.all(promises);
        res.json({ success: true, broadcastCount: promises.length });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.post('/upload', upload.single('file'), async (req, res) => {
    // sessionId ignored, we broadcast
    const file = req.file;

    if (!file) {
        return res.status(400).json({ success: false, error: 'No file uploaded' });
    }

    try {
        const fileContent = fs.readFileSync(file.path);
        const fileData = {
            inlineData: {
                data: fileContent.toString('base64'),
                mimeType: file.mimetype
            }
        };

        const promises = [];
        for (const [id, session] of sessions.entries()) {
            console.log(`Broadcasting file to session: ${id}`);
            promises.push(processText(null, id, fileData));
        }
        await Promise.all(promises);

        // Clean up
        fs.unlinkSync(file.path);

        res.json({ success: true, broadcastCount: promises.length });
    } catch (error) {
        console.error("Upload Error:", error);
        res.status(500).json({ success: false, error: error.message });
    }
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`VibroBraille Brain running on port ${PORT}`);
});
