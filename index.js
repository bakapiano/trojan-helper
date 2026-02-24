import WebSocket from "ws";
import express from "express";
import fetch from "node-fetch";
import fs from "fs";
import schedule from "node-schedule";
import subProcess from "child_process";

const HELPER_CONFIG_PATH = new URL("./helper-config.json", import.meta.url);

function readHelperConfig() {
  if (!fs.existsSync(HELPER_CONFIG_PATH)) {
    console.error("helper-config.json 不存在，请先运行 setup.sh 进行配置");
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(HELPER_CONFIG_PATH).toString());
}

const helperConfig = readHelperConfig();
const TROJAN_CONFIG_PATH = helperConfig.trojan_config_path;
const TROJAN_PASSWORD = helperConfig.trojan_password;

function readTrojanConfig() {
  const trojanConfig = JSON.parse(
    fs.readFileSync(TROJAN_CONFIG_PATH).toString(),
  );
  return {
    port: trojanConfig.local_port,
    host: trojanConfig.ssl.sni,
  };
}

const app = express();
app.get("/config.yaml", (req, res) => {
  let config = fs.readFileSync("./config.yaml").toString();
  const { host, port } = readTrojanConfig();
  config = config
    .replace("{trojan-server}", host)
    // .replace("{trojan-server}", host)
    .replace("{trojan-port}", port)
    .replace("{trojan-password}", TROJAN_PASSWORD);

  res.set("Content-Type", "application/yaml").status(200).send(config);
});
app.listen(8848);

async function ping(ip, port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket("ws://coolaf.com:9010/tool/ajaxport", {
      headers: {
        Origin: "http://coolaf.com",
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
      },
    });
    const timeout = setTimeout(() => {
      ws.close();
      resolve(false);
    }, 10000);
    ws.on("open", () => {
      ws.send(JSON.stringify({ ip, port: String(port) }));
    });
    ws.on("message", (data) => {
      try {
        const result = JSON.parse(data.toString());
        // Status "1" = open, "2" = closed
        clearTimeout(timeout);
        ws.close();
        resolve(result.Status === "1");
      } catch (e) {
        // ignore parse errors, wait for next message
      }
    });
    ws.on("error", (err) => {
      console.error("WebSocket error:", err.message);
      clearTimeout(timeout);
      resolve(false);
    });
  });
}

async function getPublicIp() {
  const res = await fetch("https://api64.ipify.org?format=json");
  return (await res.json()).ip;
}

const rule = new schedule.RecurrenceRule();
rule.minute = [];
for (var min = 0; min < 60; min += 1) rule.minute.push(min);
schedule.scheduleJob(rule, async () => {
  const PING_RETRY_COUNT = 5;
  const ip = await getPublicIp();
  const { port } = readTrojanConfig();
  console.log(ip, port);
  for (var i = 0; i < PING_RETRY_COUNT; ++i) {
    if (await ping(ip, port)) {
      return;
    }
  }
  subProcess.exec('echo "" | trojan port', (err, stdout, stderr) => {
    if (err) {
      console.error(err);
      process.exit(1);
    } else {
      console.log(`The stdout Buffer from shell: ${stdout.toString()}`);
      console.log(`The stderr Buffer from shell: ${stderr.toString()}`);
    }
  });
});
