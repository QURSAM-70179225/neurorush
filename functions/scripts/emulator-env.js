// Local-only config for the emulator test run: points the AI functions at the
// mock Groq server started by test/ai.emulator.test.ts. Never deployed.
const fs = require('fs');
fs.writeFileSync('.env.local', 'GROQ_BASE_URL=http://127.0.0.1:4599\nGROQ_MODEL=mock-llama\nBATTLE_QUESTION_MS=1500\nPUSH_DRY_RUN=true\nPLAY_API_BASE_URL=http://127.0.0.1:4598\nADMOB_KEYS_URL=http://127.0.0.1:4598/admob-keys.json\n');
fs.writeFileSync('.secret.local', 'GROQ_API_KEY=emulator-test-key\n');
