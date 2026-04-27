#!/bin/bash

echo -e "\e[36m====================================================\e[0m"
echo -e "\e[36m          Vercel XHTTP - Auto Deployer              \e[0m"
echo -e "\e[36m====================================================\e[0m"

# ۱. دریافت اطلاعات (از پارامترهای ورودی یا پرسش از کاربر)
TARGET_URL=$1
RAW_PROJECT_NAME=$2

# اگر آدرس مقصد (پارامتر اول) خالی بود بپرس
if [ -z "$TARGET_URL" ]; then
    read -p "Enter Backend Xray URL (e.g., https://xray.domain.com:2096): " TARGET_URL
    if [ -z "$TARGET_URL" ]; then
        echo -e "\e[31mKhata: Adrese maghsad nemitavanad khali bashad.\e[0m"
        exit 1
    fi
else
    echo -e "\e[32m[+] Target URL: $TARGET_URL\e[0m"
fi

# اگر نام پروژه (پارامتر دوم) خالی بود بپرس
if [ -z "$RAW_PROJECT_NAME" ]; then
    read -p "Enter Project Name (e.g., my-custom-relay): " RAW_PROJECT_NAME
fi

# پردازش نام پروژه
if [ -z "$RAW_PROJECT_NAME" ]; then
    PROJECT_NAME="vercel-xhttp-relay"
    echo -e "\e[33m[!] Nami vared nashod. Estefadeh az name pishfarz: $PROJECT_NAME\e[0m"
else
    # تبدیل نام به فرمت استاندارد ورسل (حروف کوچک، جایگزینی فاصله و کاراکترهای غیرمجاز با خط تیره)
    PROJECT_NAME=$(echo "$RAW_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    echo -e "\e[32m[+] Project Name set to: $PROJECT_NAME\e[0m"
fi

# ۲. نصب پیش‌نیازها (Node.js و npm) در صورت نیاز
if ! command -v npm &> /dev/null; then
    echo -e "\e[33m[+] Node.js and npm not found. Installing them now...\e[0m"
    apt update && apt install -y nodejs npm
fi

# ۳. بررسی و نصب Vercel CLI
if ! command -v vercel &> /dev/null; then
    echo -e "\e[33m[+] Installing Vercel CLI...\e[0m"
    npm i -g vercel
fi

# ۴. لاگین به حساب Vercel
echo -e "\e[33m\n[+] Logging into Vercel...\e[0m"
echo -e "\e[36mLotfan email khod ra vared kardeh va login konid:\e[0m"
vercel login

if [ $? -ne 0 ]; then
    echo -e "\e[31mKhata: Login be Vercel ba moshkel movajeh shod. Lotfan dobareh talash konid.\e[0m"
    exit 1
fi

# ۵. ایجاد فایل‌های پروژه در یک پوشه با نام خود پروژه
PROJECT_DIR="$PROJECT_NAME"
mkdir -p $PROJECT_DIR/api
echo -e "\e[33m\n[+] Creating project files...\e[0m"

cat > $PROJECT_DIR/api/index.js << 'EOF'
export const config = { runtime: "edge" };
const TARGET_BASE = (process.env.TARGET_DOMAIN || "").replace(/\/$/, "");
const STRIP_HEADERS = new Set(["host", "connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade", "forwarded", "x-forwarded-host", "x-forwarded-proto", "x-forwarded-port"]);

export default async function handler(req) {
  if (!TARGET_BASE) return new Response("Misconfigured: TARGET_DOMAIN is not set", { status: 500 });
  try {
    const pathStart = req.url.indexOf("/", 8);
    const targetUrl = pathStart === -1 ? TARGET_BASE + "/" : TARGET_BASE + req.url.slice(pathStart);
    const out = new Headers();
    let clientIp = null;
    for (const [k, v] of req.headers) {
      if (STRIP_HEADERS.has(k)) continue;
      if (k.startsWith("x-vercel-")) continue;
      if (k === "x-real-ip") { clientIp = v; continue; }
      if (k === "x-forwarded-for") { if (!clientIp) clientIp = v; continue; }
      out.set(k, v);
    }
    if (clientIp) out.set("x-forwarded-for", clientIp);
    return await fetch(targetUrl, { method: req.method, headers: out, body: (req.method !== "GET" && req.method !== "HEAD") ? req.body : undefined, duplex: "half", redirect: "manual" });
  } catch (err) {
    return new Response("Bad Gateway: Tunnel Failed", { status: 502 });
  }
}
EOF

cat > $PROJECT_DIR/package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "1.0.0",
  "private": true
}
EOF

cat > $PROJECT_DIR/vercel.json << EOF
{
  "version": 2,
  "name": "$PROJECT_NAME",
  "rewrites": [{ "source": "/(.*)", "destination": "/api/index" }]
}
EOF

cd $PROJECT_DIR

# ۶. پیکربندی و استقرار روی Vercel به صورت قطعی
echo -e "\e[33m\n[+] Deploying to Vercel and injecting variables...\e[0m"

# لینک کردن اولیه به اکانت ورسل
vercel link --yes

# حذف متغیر قبلی در صورت وجود (برای جلوگیری از تداخل)
vercel env rm TARGET_DOMAIN --yes 2>/dev/null || true

# ثبت متغیر در تنظیمات پروژه بدون نیاز به دخالت کاربر
echo -n "$TARGET_URL" | vercel env add TARGET_DOMAIN production

# آپلود نهایی + تزریق مستقیم متغیر محیطی
DEPLOY_URL=$(vercel --prod --env TARGET_DOMAIN="$TARGET_URL" --yes)

# ساخت نام دامنه اصلی (Main Domain) و حذف https:// از لینک Deployment
MAIN_DOMAIN="${PROJECT_NAME}.vercel.app"
DEPLOY_DOMAIN=$(echo "$DEPLOY_URL" | awk -F/ '{print $3}')

echo -e "\e[32m\n====================================================\e[0m"
echo -e "\e[32m            ✅ Esteghrar ba movafaghiyat anjam shod!             \e[0m"
echo -e "\e[32m====================================================\e[0m"
echo -e "📌 Main Domain (Host/SNI): \e[36m$MAIN_DOMAIN\e[0m"
echo -e "📌 Deployment URL (Temp):  \e[90m$DEPLOY_DOMAIN\e[0m"
echo -e "📌 Target Backend:         \e[33m$TARGET_URL\e[0m"
echo -e "----------------------------------------------------"
echo -e "\e[33mHala mitavanid adrese '$MAIN_DOMAIN' ra dar bakhshe 'host' va 'sni' client khod gharar dahid.\e[0m"
echo -e "\e[32m====================================================\e[0m"

# ۷. خروج و پاکسازی
echo -e "\e[33m\n[!] Logging out from Vercel CLI to clear session...\e[0m"
vercel logout
cd ..
rm -rf $PROJECT_DIR
echo -e "\e[32m[+] Vercel session cleared and temporary files removed. Script is ready for another run.\e[0m"
