--[[--
A light panchang: today's tithi, nakshatra and Rahu Kalam, computed on the
device. Sun and Moon longitudes use the main terms from Meeus' "Astronomical
Algorithms"; the nakshatra uses the Lahiri ayanamsa. Tithi changes land within
minutes of a full panchang. Rahu Kalam is the weekday's eighth of daylight,
from the sunrise and sunset the weather service provides.
--]]--
local Panchang = {}

local TITHI = {
    te = { "పాడ్యమి", "విదియ", "తదియ", "చవితి", "పంచమి", "షష్ఠి", "సప్తమి", "అష్టమి",
           "నవమి", "దశమి", "ఏకాదశి", "ద్వాదశి", "త్రయోదశి", "చతుర్దశి" },
    en = { "Pratipada", "Dwitiya", "Tritiya", "Chaturthi", "Panchami", "Shashthi", "Saptami", "Ashtami",
           "Navami", "Dashami", "Ekadashi", "Dwadashi", "Trayodashi", "Chaturdashi" },
}
local PAKSHA = { te = { "శుద్ధ", "బహుళ" }, en = { "Shukla", "Krishna" } }
local FULL = { te = "పౌర్ణమి", en = "Purnima" }
local NEW = { te = "అమావాస్య", en = "Amavasya" }
local NAKSHATRA = {
    te = { "అశ్విని", "భరణి", "కృత్తిక", "రోహిణి", "మృగశిర", "ఆరుద్ర", "పునర్వసు",
           "పుష్యమి", "ఆశ్లేష", "మఖ", "పుబ్బ", "ఉత్తర", "హస్త", "చిత్త", "స్వాతి", "విశాఖ", "అనూరాధ", "జ్యేష్ఠ", "మూల",
           "పూర్వాషాఢ", "ఉత్తరాషాఢ", "శ్రవణం", "ధనిష్ఠ", "శతభిషం", "పూర్వాభాద్ర", "ఉత్తరాభాద్ర", "రేవతి" },
    en = { "Ashwini", "Bharani", "Krittika", "Rohini", "Mrigashira", "Ardra", "Punarvasu",
           "Pushya", "Ashlesha", "Magha", "Purva Phalguni", "Uttara Phalguni", "Hasta", "Chitra", "Swati", "Vishakha",
           "Anuradha", "Jyeshtha", "Mula", "Purva Ashadha", "Uttara Ashadha", "Shravana", "Dhanishta", "Shatabhisha",
           "Purva Bhadrapada", "Uttara Bhadrapada", "Revati" },
}
Panchang.LABEL = {
    te = { rahu = "రాహుకాలం" },
    en = { rahu = "Rahu Kalam" },
}
-- Rahu Kalam's eighth of the day (1-8) for Sunday..Saturday
local RAHU_PART = { 8, 2, 7, 5, 6, 4, 3 }

local rad = math.pi / 180
local function sin(deg) return math.sin(deg * rad) end
local function norm(deg)
    deg = deg % 360
    if deg < 0 then deg = deg + 360 end
    return deg
end

-- Julian centuries since J2000 for a Unix time in seconds
local function centuries(t)
    return (t / 86400 + 2440587.5 - 2451545.0) / 36525
end

-- tropical longitude of the Sun
local function sun(T)
    local M = norm(357.52911 + 35999.05029 * T)
    local L0 = norm(280.46646 + 36000.76983 * T)
    return L0 + (1.914602 - 0.004817 * T) * sin(M) + 0.019993 * sin(2 * M) + 0.000289 * sin(3 * M)
end

-- tropical longitude of the Moon
local function moon(T)
    local M = norm(357.52911 + 35999.05029 * T)
    local Lp = norm(218.3164477 + 481267.88123421 * T)
    local D = norm(297.8501921 + 445267.1114034 * T)
    local Mp = norm(134.9633964 + 477198.8675055 * T)
    local F = norm(93.2720950 + 483202.0175233 * T)
    return norm(Lp + 6.288774 * sin(Mp) + 1.274027 * sin(2 * D - Mp) + 0.658314 * sin(2 * D)
        + 0.213618 * sin(2 * Mp) - 0.185116 * sin(M) - 0.114332 * sin(2 * F)
        + 0.058793 * sin(2 * D - 2 * Mp) + 0.057066 * sin(2 * D - M - Mp) + 0.053322 * sin(2 * D + Mp)
        + 0.045758 * sin(2 * D - M) - 0.040923 * sin(M - Mp) - 0.034720 * sin(D) - 0.030383 * sin(M + Mp))
end

local function ayanamsa(T) return 23.85305 + 1.39689 * T end

-- 0-14 Shukla Pratipada..Purnima, 15-29 Krishna Pratipada..Amavasya
function Panchang.tithiIndex(t)
    local T = centuries(t)
    return math.min(29, math.floor(norm(moon(T) - sun(T)) / 12))
end

function Panchang.tithi(t, lang)
    lang = TITHI[lang] and lang or "en"
    local i = Panchang.tithiIndex(t)
    if i == 14 then return FULL[lang] end
    if i == 29 then return NEW[lang] end
    return PAKSHA[lang][i < 15 and 1 or 2] .. " " .. TITHI[lang][(i % 15) + 1]
end

function Panchang.nakshatra(t, lang)
    lang = NAKSHATRA[lang] and lang or "en"
    local T = centuries(t)
    local sidereal = norm(moon(T) - ayanamsa(T))
    return NAKSHATRA[lang][math.min(26, math.floor(sidereal / (360 / 27))) + 1]
end

-- Rahu Kalam {start, end} (Unix seconds) for the day of `sunrise`
function Panchang.rahuKalam(sunrise, sunset)
    if not sunrise or not sunset or sunset <= sunrise then return nil end
    local wday = tonumber(os.date("%w", sunrise)) -- 0 = Sunday
    local part = RAHU_PART[wday + 1]
    local eighth = (sunset - sunrise) / 8
    local start = sunrise + eighth * (part - 1)
    return start, start + eighth
end

return Panchang
