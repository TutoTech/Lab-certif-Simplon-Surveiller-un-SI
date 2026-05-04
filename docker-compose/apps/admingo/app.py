"""
AdminGo — application minimale de révision pour TutoTech.
Volontairement simple : page d'accueil + endpoint de quiz factice.
La vraie application est étendue ailleurs ; ce code sert au lab.
"""

import os
from flask import Flask, request, jsonify, render_template_string

app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY", "dev-only")

QUESTIONS = [
    {"id": 1, "q": "Quelle commande liste les VMs sur Proxmox ?", "a": "qm list"},
    {"id": 2, "q": "Quel port utilise Wazuh manager pour les agents ?", "a": "1514"},
    {"id": 3, "q": "Quelle option Suricata active la sortie EVE JSON ?", "a": "outputs.eve-log.enabled"},
]


@app.route("/")
def index():
    return render_template_string(
        """
        <!doctype html>
        <html lang="fr">
        <head>
          <meta charset="utf-8">
          <title>AdminGo — TutoTech</title>
          <style>
            body { font-family: system-ui, sans-serif; max-width: 720px; margin: 4em auto; padding: 0 1em; }
            h1 { color: #1F4E79; }
            .badge { background: #2E75B6; color: #fff; padding: 0.2em 0.6em; border-radius: 0.5em; font-size: 0.8em; }
          </style>
        </head>
        <body>
          <h1>AdminGo <span class="badge">TutoTech Lab</span></h1>
          <p>Application de révision pour la préparation aux certifications.</p>
          <p>Endpoints disponibles :
            <ul>
              <li><code>GET /quiz</code> — liste des questions</li>
              <li><code>GET /quiz/&lt;id&gt;</code> — détail d'une question</li>
              <li><code>POST /answer</code> — soumettre une réponse</li>
              <li><code>GET /healthz</code> — health check</li>
            </ul>
          </p>
        </body>
        </html>
        """
    )


@app.route("/quiz")
def quiz_list():
    return jsonify([{"id": q["id"], "q": q["q"]} for q in QUESTIONS])


@app.route("/quiz/<int:qid>")
def quiz_detail(qid):
    item = next((q for q in QUESTIONS if q["id"] == qid), None)
    if not item:
        return jsonify({"error": "not_found"}), 404
    return jsonify({"id": item["id"], "q": item["q"]})


@app.route("/answer", methods=["POST"])
def answer():
    payload = request.get_json(silent=True) or {}
    qid = payload.get("id")
    user_ans = payload.get("answer", "").strip().lower()
    item = next((q for q in QUESTIONS if q["id"] == qid), None)
    if not item:
        return jsonify({"error": "unknown_question"}), 400
    correct = user_ans == item["a"].lower()
    return jsonify({"id": qid, "correct": correct})


@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
