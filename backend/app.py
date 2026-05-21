from flask import Flask, jsonify, request
import requests
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

# Load from environment variables (you can create a .env file in the backend folder)
AZURE_SPEECH_KEY = os.getenv("AZURE_SPEECH_KEY", "AZURE_KEY_NOT_SET")
AZURE_REGION = os.getenv("AZURE_REGION", "eastasia") 

@app.route('/api/azure-token', methods=['GET'])
def get_azure_token():
    """
    Fetches a short-lived authorization token from Azure Cognitive Services.
    This token is valid for 10 minutes.
    """
    if AZURE_SPEECH_KEY == "YOUR_AZURE_KEY":
        return jsonify({"error": "Azure key not configured on backend."}), 500

    token_url = f"https://{AZURE_REGION}.api.cognitive.microsoft.com/sts/v1.0/issueToken"
    
    headers = {
        'Ocp-Apim-Subscription-Key': AZURE_SPEECH_KEY
    }
    
    try:
        response = requests.post(token_url, headers=headers)
        response.raise_for_status() # Raise an exception for bad status codes
        
        # The response body is the token itself as a plain text string
        token = response.text
        return jsonify({"token": token})
        
    except requests.exceptions.RequestException as e:
        print(f"Error fetching token: {e}")
        return jsonify({"error": "Failed to fetch token from Azure"}), 500

if __name__ == '__main__':
    # Run the Flask app on port 5000
    app.run(host='0.0.0.0', port=5000, debug=True)
