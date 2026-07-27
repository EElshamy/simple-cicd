const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>Simple CI/CD Project</title>

        <style>
            *{
                margin:0;
                padding:0;
                box-sizing:border-box;
                font-family:Arial, Helvetica, sans-serif;
            }

            body{
                background:#0f172a;
                color:white;
                display:flex;
                justify-content:center;
                align-items:center;
                height:100vh;
            }

            .card{
                background:#1e293b;
                padding:50px;
                border-radius:18px;
                text-align:center;
                width:650px;
                box-shadow:0 15px 40px rgba(0,0,0,.4);
            }

            h1{
                font-size:40px;
                margin-bottom:20px;
            }

            p{
                color:#cbd5e1;
                font-size:18px;
                margin-bottom:30px;
            }

            .status{
                display:inline-block;
                padding:12px 25px;
                background:#22c55e;
                border-radius:10px;
                font-weight:bold;
                margin-bottom:30px;
            }

            .tech{
                display:flex;
                justify-content:center;
                flex-wrap:wrap;
                gap:12px;
            }

            .tech span{
                background:#334155;
                padding:10px 18px;
                border-radius:30px;
            }

            footer{
                margin-top:35px;
                color:#94a3b8;
                font-size:14px;
            }
        </style>

    </head>

    <body>

        <div class="card">

            <h1>🚀 CI/CD Pipeline</h1>

            <p>
                Automated Build, Test and Docker Deployment using GitHub Actions
            </p>

            <div class="status">
                ✅ Application Running Successfully
            </div>

            <div class="tech">
                <span>Node.js</span>
                <span>Express</span>
                <span>Docker</span>
                <span>Docker Compose</span>
                <span>GitHub Actions</span>
            </div>

            <footer>
                Built by Eslam Elshamy ❤️
            </footer>

        </div>

    </body>
    </html>
  `);
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
