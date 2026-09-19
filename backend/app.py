from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
CORS(app)

DATABASE_URL = os.getenv("DATABASE_URL")


def get_db():
    return psycopg.connect(DATABASE_URL)


@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok"
    })


@app.route("/api/expenses", methods=["POST"])
def create_expense():
    data = request.get_json()

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


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True,
    )
