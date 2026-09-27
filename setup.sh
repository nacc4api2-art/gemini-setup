#!/usr/bin/env bash
# =====================================================================
#  Gemini Keys Provisioner — Google Cloud Shell Edition
#  يعمل داخل Google Cloud Shell فقط (gcloud مصادق تلقائيًا بحساب المستخدم)
# =====================================================================

# ------------------------- إعدادات المالك (عدّلها مرة واحدة) -------------------------
KEYS_PER_USER=10                            # عدد المشاريع/المفاتيح لكل مستخدم
GAS_URL="https://script.google.com/macros/s/AKfycbxbVQPI_bR6V3shcvH9rucqJbnC1E7NC0MgIp1Zadt9oAAdm7wdMQNO0yPZmkbzvZUc/exec"        # رابط تطبيق الويب من Google Apps Script
SHARED_SECRET="MySecret2026XYZ"           # السر المشترك (نفس الموجود في كود المستقبل)
SERVICE_LABEL="مساعدك الذكي"                # اسم خدمتك كما يظهر في رسالة الإفصاح
# -------------------------------------------------------------------------------------

CYN='\033[0;36m'; GRN='\033[0;32m'; YLW='\033[0;33m'; RED='\033[0;31m'; RST='\033[0m'
say()  { printf "${CYN}[%s]${RST} %s\n" "$(date +%H:%M:%S)" "$1"; }
ok()   { printf "${GRN}[OK]${RST} %s\n" "$1"; }
warn() { printf "${YLW}[!]${RST} %s\n" "$1"; }
die()  { printf "${RED}[X]${RST} %s\n" "$1"; exit 1; }

# ------------------------- فحص الإعدادات -------------------------
if [[ "$GAS_URL" == *"PASTE_APPS_SCRIPT_URL"* || -z "$GAS_URL" ]]; then
  die "لم يتم ضبط رابط Apps Script (GAS_URL) داخل السكربت."
fi
if [[ "$SHARED_SECRET" == *"PASTE_SECRET"* || -z "$SHARED_SECRET" ]]; then
  die "لم يتم ضبط السر المشترك (SHARED_SECRET) داخل السكربت."
fi

# ------------------------- الإفصاح والموافقة -------------------------
echo "=========================================================="
echo "        إعداد مساعد Gemini الذكي — ${SERVICE_LABEL}"
echo "=========================================================="
echo
echo "قبل البدء، من المهم أن تعرف ماذا سيفعل هذا الإعداد بحسابك:"
echo "  1) إنشاء ${KEYS_PER_USER} مشاريع جديدة على Google Cloud في حسابك أنت."
echo "  2) توليد مفتاح Gemini API واحد داخل كل مشروع."
echo "  3) إرسال المفاتيح المرتبطة بحسابك (بريدك الإلكتروني) إلى خدمة"
echo "     \"${SERVICE_LABEL}\" لتُستخدم من حسابك داخل التطبيق."
echo "  لن يتم استخدام حسابك في أي شيء آخر، ويمكنك حذف المشاريع أو"
echo "  المفاتيح في أي وقت من حسابك على Google Cloud."
echo
printf "للمتابعة اكتب نعم ثم اضغط Enter: "
read -r ANSWER
if [[ ! "$ANSWER" =~ ^(نعم|yes|y|Y|Yes|YES)$ ]]; then
  die "تم الإلغاء — لم يتغير أي شيء في حسابك."
fi

# ------------------------- التحقق من البيئة -------------------------
command -v gcloud >/dev/null 2>&1 || die "gcloud غير موجود — شغّل السكربت داخل Google Cloud Shell."
EMAIL=$(gcloud config get-value account 2>/dev/null | head -n1 | tr -d '[:space:]')
if [ -z "$EMAIL" ] || [ "$EMAIL" == "(unset)" ]; then
  die "لم يتم التعرف على حساب Google — أعد فتح الرابط وتأكد من تسجيل الدخول."
fi
say "الحساب: ${EMAIL}"

STAMP=$(date +%s)
RUN_ID=$(date +%Y%m%d_%H%M%S)
KEYS_FILE="$HOME/gemini_keys_${RUN_ID}.txt"
CREATED=0
declare -a MASKED_KEYS
declare -a PROJECT_IDS

# دالة إرسال مفتاح واحد إلى Google Sheet (محاولتان)
send_key() {
  local prj="$1" key="$2" resp
  for attempt in 1 2; do
    resp=$(curl -L -s --max-time 30 -X POST "$GAS_URL" \
      --data-urlencode "secret=${SHARED_SECRET}" \
      --data-urlencode "email=${EMAIL}" \
      --data-urlencode "project=${prj}" \
      --data-urlencode "key=${key}" 2>/dev/null)
    if [[ "$resp" == *'"ok":true'* ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# ------------------------- الحلقة الرئيسية -------------------------
for i in $(seq 1 "$KEYS_PER_USER"); do
  RND=$((RANDOM % 90000 + 10000))
  PROJECT_ID="gen-ai-${STAMP}-${RND}"
  PROJECT_NAME="Gemini Project ${i}"

  say "(${i}/${KEYS_PER_USER}) إنشاء المشروع: ${PROJECT_ID} ..."
  if ! CREATE_OUT=$(gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME" --quiet 2>&1); then
    echo "$CREATE_OUT" | tail -n 5
    warn "توقف عند إنشاء المشروع رقم ${i}."
    warn "أشهر الأسباب: كوتة إنشاء المشاريع انتهت، أو الحساب جديد ويحتاج قبول شروط Google Cloud."
    warn "الحل: افتح console.cloud.google.com مرة واحدة ووافق على الشروط ثم أعد تشغيل الأمر."
    break
  fi
  ok "تم إنشاء المشروع: ${PROJECT_ID}"

  sleep 8   # انتشار المشروع قبل تفعيل الخدمات

  say "تفعيل الخدمات (Generative Language + API Keys) ..."
  if ! gcloud services enable generativelanguage.googleapis.com apikeys.googleapis.com \
       --project="$PROJECT_ID" --quiet >/dev/null 2>&1; then
    sleep 10
    gcloud services enable generativelanguage.googleapis.com apikeys.googleapis.com \
       --project="$PROJECT_ID" --quiet >/dev/null 2>&1 || { warn "فشل تفعيل الخدمات — تم تجاوز هذا المشروع."; continue; }
  fi

  say "إنشاء مفتاح API ..."
  gcloud services api-keys create --display-name="GeminiKey-${i}" \
    --project="$PROJECT_ID" --quiet >/dev/null 2>&1

  KEY_NAME=""
  for t in 1 2 3 4 5; do
    KEY_NAME=$(gcloud services api-keys list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | head -n1)
    [ -n "$KEY_NAME" ] && break
    sleep 3
  done
  if [ -z "$KEY_NAME" ]; then
    warn "لم يتم العثور على المفتاح في ${PROJECT_ID} — تم تجاوزه."
    continue
  fi

  sleep 3
  API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --location="global" --format="value(keyString)" 2>/dev/null | head -n1)

  if [[ "$API_KEY" =~ ^AIza[0-9A-Za-z_-]{30,}$ ]]; then
    # فحص سريع أن المفتاح يعمل فعلاً (غير حاسم)
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 \
      "https://generativelanguage.googleapis.com/v1beta/models?key=${API_KEY}")
    if [ "$HTTP" = "200" ]; then
      ok "المفتاح (${i}) شغال — ...${API_KEY: -4}"
    else
      warn "المفتاح (${i}) اتولد لكن فحص التشغيل رجع ${HTTP} — سيتم إرساله على أي حال."
    fi

    echo "${EMAIL} | ${PROJECT_ID} | ${API_KEY}" >> "$KEYS_FILE"
    MASKED_KEYS+=("...${API_KEY: -4} (${PROJECT_ID})")
    PROJECT_IDS+=("$PROJECT_ID")
    CREATED=$((CREATED+1))

    if send_key "$PROJECT_ID" "$API_KEY"; then
      ok "تم إرسال المفتاح (${i}) وربطه بحسابك في الخدمة."
    else
      warn "تعذر إرسال المفتاح (${i}) الآن — لكنه محفوظ محليًا في: ${KEYS_FILE}"
    fi
  else
    warn "فشل جلب نص المفتاح من ${PROJECT_ID} — تم تجاوزه."
  fi

  sleep 5
done

# ------------------------- الملخص النهائي -------------------------
echo
echo "=========================================================="
echo "                     النتيجة النهائية"
echo "=========================================================="
if [ "$CREATED" -gt 0 ]; then
  ok "تم إنشاء ${CREATED} مفتاح لصالح ${EMAIL}"
  echo
  for k in "${MASKED_KEYS[@]}"; do
    echo "   • ${k}"
  done
  echo
  ok "نسخة احتياطية محفوظة في حسابك: ${KEYS_FILE}"
  ok "تم إرسال المفاتيح وربطها بحسابك في خدمة ${SERVICE_LABEL}."
  echo "  يمكنك حذف المشاريع في أي وقت من: console.cloud.google.com"
else
  warn "لم يتم إنشاء أي مفاتيح في هذه الجلسة."
fi
echo "=========================================================="
