import express from "express";
import fetch from "node-fetch";
import fs from "fs";
import schedule from "node-schedule"
import subProcess from "child_process";

const TROJAN_CONFIG_PATH = "./config.json"
const TROJAN_PASSWORD = ""

function readTrojanConfig() {
    const trojanConfig = JSON.parse(fs.readFileSync(TROJAN_CONFIG_PATH).toString())
    return {
        port: trojanConfig.local_port,
        host: trojanConfig.ssl.sni,
    }
}

const app = express()
app.get("/config.yaml", (req, res) => {
    let config = fs.readFileSync("./config.yaml").toString()
    const { host, port } = readTrojanConfig()
    config = config
        .replace("{trojan-server}", host)
        // .replace("{trojan-server}", host)
        .replace("{trojan-port}", port)
        .replace("{trojan-password}", TROJAN_PASSWORD)
        
    res.set('Content-Type', 'application/yaml').status(200).send(config)
})
app.listen(8848)

async function ping(ip, port) {
    const res = await fetch(`https://yuanxiapi.cn/api/port/?ip=${ip}&port=${port}`)
    return (await res.json()).port[port] === "开启" 
}

async function getPublicIp() {
    const res = await fetch('https://api64.ipify.org?format=json')
    return (await res.json()).ip
}

const rule = new schedule.RecurrenceRule()
rule.minute = []
for (var min = 0; min < 60; min += 1) rule.minute.push(min)
schedule.scheduleJob(rule, async () => {
    const PING_RETRY_COUNT = 5
    const ip = await getPublicIp()
    const { port } = readTrojanConfig()
    console.log(ip, port)
    for (var i = 0; i < PING_RETRY_COUNT; ++i) {
        if (ping(ip, port)) {
            return
        }
    }
    subProcess.exec('echo "" | trojan port', (err, stdout, stderr) => {
        if (err) {
            console.error(err)
            process.exit(1)
        } else {
            console.log(`The stdout Buffer from shell: ${stdout.toString()}`)
            console.log(`The stderr Buffer from shell: ${stderr.toString()}`)
        }
    })
})