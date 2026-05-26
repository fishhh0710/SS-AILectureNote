from flask import Flask, jsonify, request
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

# Load from environment variables
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "YOUR_GEMINI_KEY")

@app.route('/api/gemini-token', methods=['GET'])
def get_gemini_token():
    """
    Provides the Gemini API Key securely to the Flutter client.
    """
    if GEMINI_API_KEY == "YOUR_GEMINI_KEY" or not GEMINI_API_KEY:
        return jsonify({"error": "Gemini API key not configured on backend."}), 500

    # For a real production app, you would add authentication here 
    # to ensure only your app can request the key.
    return jsonify({"key": GEMINI_API_KEY})

if __name__ == '__main__':
    # Run the Flask app on port 5001 so it doesn't conflict with app.py
    app.run(host='0.0.0.0', port=5001, debug=True)
