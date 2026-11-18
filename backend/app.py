from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg
import os
from dotenv import load_dotenv
import requests
import json
import re


# --------------------------------------------------
# Load environment variables
# --------------------------------------------------

load_dotenv()


# --------------------------------------------------
# Flask setup
# --------------------------------------------------

app = Flask(__name__)
CORS(app)


# --------------------------------------------------
# Database
# --------------------------------------------------

DATABASE_URL = os.getenv("DATABASE_URL")


def get_db():
    return psycopg.connect(DATABASE_URL)


# --------------------------------------------------
# Health check
# --------------------------------------------------

@app.route("/api/health", methods=["GET"])
def health():

    return jsonify({
        "status": "ok"
    })


# --------------------------------------------------
# Create expense manually
# --------------------------------------------------

@app.route("/api/expenses", methods=["POST"])
def create_expense():

    data = request.get_json()

    if not data:
        return jsonify({
            "error": "No JSON data provided"
        }), 400

    required = [
        "amount",
        "category",
        "description",
        "date"
    ]

    for field in required:

        if field not in data:

            return jsonify({
                "error": f"Missing field: {field}"
            }), 400

    with get_db() as conn:

        with conn.cursor() as cur:

            cur.execute(
                """
                INSERT INTO expenses
                (amount, category, description, date)
                VALUES (%s, %s, %s, %s)
                RETURNING id
                """,
                (
                    data["amount"],
                    data["category"],
                    data["description"],
                    data["date"],
                ),
            )

            expense_id = cur.fetchone()[0]

        conn.commit()

    return jsonify({
        "id": expense_id,
        "message": "Expense saved"
    }), 201


# --------------------------------------------------
# Get all expenses
# --------------------------------------------------

@app.route("/api/expenses", methods=["GET"])
def get_expenses():

    with get_db() as conn:

        with conn.cursor() as cur:

            cur.execute(
                """
                SELECT
                    id,
                    amount,
                    category,
                    description,
                    date,
                    created_at
                FROM expenses
                ORDER BY date DESC, id DESC
                """
            )

            rows = cur.fetchall()

    expenses = []

    for row in rows:

        expenses.append({
            "id": row[0],
            "amount": float(row[1]),
            "category": row[2],
            "description": row[3],
            "date": str(row[4]),
            "created_at": str(row[5]),
        })

    return jsonify(expenses)


# --------------------------------------------------
# Ollama expense processing
# --------------------------------------------------

def process_with_ollama(raw_text, created_at):

    prompt = f"""
You are an expense extraction system.

The user's expense message is:

{raw_text}

The message was created at:
{created_at}

Return ONLY valid JSON.

Required format:

{{
  "amount": <number from the message>,
  "category": "<one allowed category>",
  "description": "<short description>",
  "date": "YYYY-MM-DD"
}}

Examples (created at 2026-01-10):

"24 tea" -> {{"amount": 24, "category": "Food", "description": "Tea", "date": "2026-01-10"}}
"tea 24" -> {{"amount": 24, "category": "Food", "description": "Tea", "date": "2026-01-10"}}
"auto80" -> {{"amount": 80, "category": "Transport", "description": "Auto", "date": "2026-01-10"}}
"spent 150 on lunch yesterday" -> {{"amount": 150, "category": "Food", "description": "Lunch", "date": "2026-01-09"}}

Allowed categories:

Food
Transport
Shopping
Bills
Entertainment
Education
Health
Other

Rules:

- amount must be a number
- amount is the number written in the message, whether it
  comes before or after the item, with or without a space
- Never return 0 for amount if the message contains a number
- date must be YYYY-MM-DD
- Resolve relative dates using the creation date
- If category is unclear, use Other
- Keep description short
- Do not add any extra text outside the JSON
"""

    response = requests.post(
        "http://127.0.0.1:11434/api/chat",

        json={
            "model": "qwen3:8b",
            "stream": False,
            "think": False,

            "messages": [
                {
                    "role": "system",
                    "content": prompt,
                }
            ],
        },

        timeout=120,
    )

    response.raise_for_status()

    data = response.json()

    content = data["message"]["content"]

    # Remove markdown code fences if Qwen adds them
    content = (
        content
        .replace("```json", "")
        .replace("```", "")
        .strip()
    )

    # Find JSON object
    start = content.find("{")
    end = content.rfind("}")

    if start == -1 or end == -1:

        raise ValueError(
            f"Qwen did not return valid JSON: {content}"
        )

    json_content = content[start:end + 1]

    return json.loads(json_content)


AMOUNT_PATTERN = re.compile(r"(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?")


def amount_from_text(text):

    match = AMOUNT_PATTERN.search(text)

    if not match:
        return None

    return float(match.group(0).replace(",", ""))


# --------------------------------------------------
# Sync expense from mobile app
# --------------------------------------------------

@app.route("/api/sync", methods=["POST"])
def sync_expense():

    data = request.get_json()

    if not data:

        return jsonify({
            "success": False,
            "error": "No data provided"
        }), 400


    # ----------------------------------------------
    # Get raw data from phone
    # ----------------------------------------------

    raw_text = data.get("raw_text", "").strip()

    created_at = data.get("created_at")


    # ----------------------------------------------
    # Validate input
    # ----------------------------------------------

    if not raw_text:

        return jsonify({
            "success": False,
            "error": "raw_text is required"
        }), 400


    if not created_at:

        return jsonify({
            "success": False,
            "error": "created_at is required"
        }), 400


    try:

        # ------------------------------------------
        # Send raw expense to Qwen
        # ------------------------------------------

        parsed = process_with_ollama(
            raw_text,
            created_at,
        )


        # ------------------------------------------
        # Validate Qwen response
        # ------------------------------------------

        required = [
            "amount",
            "category",
            "description",
            "date",
        ]

        for field in required:

            if field not in parsed:

                raise ValueError(
                    f"Qwen missing field: {field}"
                )


        # ------------------------------------------
        # Validate amount
        # ------------------------------------------

        try:

            amount = float(parsed["amount"])

        except (ValueError, TypeError):

            amount = 0.0


        # Safety net: if the model missed the amount,
        # use the number written in the message.
        if amount <= 0:

            fallback = amount_from_text(raw_text)

            if fallback is None:

                raise ValueError(
                    "Could not find an amount in the message"
                )

            amount = fallback


        # ------------------------------------------
        # Validate category
        # ------------------------------------------

        allowed_categories = [
            "Food",
            "Transport",
            "Shopping",
            "Bills",
            "Entertainment",
            "Education",
            "Health",
            "Other",
        ]

        category = parsed["category"]

        if category not in allowed_categories:

            category = "Other"


        # ------------------------------------------
        # Save processed expense to PostgreSQL
        # ------------------------------------------

        with get_db() as conn:

            with conn.cursor() as cur:

                cur.execute(
                    """
                    INSERT INTO expenses
                    (amount, category, description, date)
                    VALUES (%s, %s, %s, %s)
                    RETURNING id
                    """,

                    (
                        amount,
                        category,
                        parsed["description"],
                        parsed["date"],
                    ),
                )

                expense_id = cur.fetchone()[0]

            conn.commit()


        # ------------------------------------------
        # Return success to phone
        # ------------------------------------------

        return jsonify({

            "success": True,

            "server_id": expense_id,

            "expense": {
                "amount": amount,
                "category": category,
                "description": parsed["description"],
                "date": parsed["date"],
            }

        }), 201


    except requests.exceptions.RequestException as e:

        return jsonify({

            "success": False,

            "error": f"Ollama connection error: {str(e)}"

        }), 503


    except json.JSONDecodeError as e:

        return jsonify({

            "success": False,

            "error": f"Invalid JSON from Qwen: {str(e)}"

        }), 500


    except psycopg.Error as e:

        return jsonify({

            "success": False,

            "error": f"Database error: {str(e)}"

        }), 500


    except Exception as e:

        return jsonify({

            "success": False,

            "error": str(e)

        }), 500


# --------------------------------------------------
# Run Flask server
# --------------------------------------------------

if __name__ == "__main__":

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True,
    )