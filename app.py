from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    # Read a secret password from an environment variable
    secret_password = os.environ.get("MY_SECRET_PASSWORD", "No Secret Set!")
    return f"<h1>Hello DevSecOps!</h1><p>The secret is: {secret_password}</p>"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)