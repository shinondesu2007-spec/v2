--==================================================
-- RELWX x CULTIVATION AUTO  (วางต่อท้ายบรรทัด Category("ฟังก์ชัน", "Functions", "sliders"))
--==================================================
;(function()
    ------------------------------------------------ 1) Config keys (เซฟ/โหลดอัตโนมัติ)
    local ND = {
        AutoAscend = false, AscendEvery = 60, AscendViaUI = false,
        AutoBreak = false, BreakEvery = 0.05,
        AutoBuyTech = false, BuyEvery = 0.05,
        AutoMeditate = false,
        AutoBossFlow = false, AutoBossTap = false, TapEvery = 0.15, AutoPerfectRing = false,
        AutoDodgePerfect = false, AutoDodgeSpam = false, PerfectLead = 20,
        AutoTower = false, AutoTowerRemote = false, AutoDungeon = false, LearnEvery = 2,
        AutoPill = false, PillEvery = 5,
        AutoBooks = false, AutoFlesh = false, ItemEvery = 10,
        AutoClaim = false, ClaimEvery = 30,
        AntiAFK = false,
    }
    for k, v in pairs(ND) do
        Defaults[k] = v
        Config[k] = v
    end
    pcall(function()
        if isfile and readfile and isfile(CONFIG_FILE) then
            local d = HttpService:JSONDecode(readfile(CONFIG_FILE))
            for k, v in pairs(ND) do
                if type(d[k]) == type(v) then
                    Config[k] = d[k]
                end
            end
        end
    end)

    ------------------------------------------------ 2) ตัวช่วย: remote / UI / กดปุ่ม
    local F = {} -- สถานะสวิตช์ (อัปเดตจาก Toggle callback)
    local Svc = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
    Svc = Svc and Svc:FindFirstChild("Knit")
    Svc = Svc and Svc:FindFirstChild("Services")
    local VIM = game:GetService("VirtualInputManager")
    local VU = game:GetService("VirtualUser")

    local RC = {}
    local function Rm(svc, kind, name)
        local key = svc .. kind .. name
        if RC[key] and RC[key].Parent then
            return RC[key]
        end
        local s = Svc and Svc:FindFirstChild(svc)
        local k = s and s:FindFirstChild(kind)
        RC[key] = k and k:FindFirstChild(name)
        return RC[key]
    end

    local function Call(r, ...)
        if not r then
            return false
        end
        local a = table.pack(...)
        return pcall(function()
            if r:IsA("RemoteFunction") then
                return r:InvokeServer(table.unpack(a, 1, a.n))
            end
            r:FireServer(table.unpack(a, 1, a.n))
        end)
    end

    local function Find(path)
        local o = PlayerGui:FindFirstChild("AscensionUI")
        for part in string.gmatch(path, "[^/]+") do
            if not o then
                return nil
            end
            o = o:FindFirstChild(part)
        end
        return o
    end

    local function Shown(o)
        if not o then
            return false
        end
        while o and o ~= PlayerGui do
            if o:IsA("GuiObject") and not o.Visible then
                return false
            end
            if o:IsA("ScreenGui") and not o.Enabled then
                return false
            end
            o = o.Parent
        end
        return true
    end

    -- กดปุ่มของเกมเอง (ยิง signal ตรง ๆ ถ้าไม่ได้ค่อยใช้คลิกจำลอง)
    local function Press(b)
        if not (b and b.Parent) then
            return false
        end
        local fired = false
        if getconnections then
            for _, sig in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down" }) do
                local ok, cs = pcall(getconnections, b[sig])
                if ok and cs then
                    for _, c in ipairs(cs) do
                        if pcall(function() c:Fire() end) then
                            fired = true
                        end
                    end
                end
            end
        end
        if not fired then
            local p = b.AbsolutePosition + b.AbsoluteSize / 2
            local sg = b:FindFirstAncestorOfClass("ScreenGui")
            local inset = (sg and sg.IgnoreGuiInset) and Vector2.new(0, 0) or GuiService:GetGuiInset()
            pcall(function()
                VIM:SendMouseButtonEvent(p.X + inset.X, p.Y + inset.Y, 0, true, game, 0)
                VIM:SendMouseButtonEvent(p.X + inset.X, p.Y + inset.Y, 0, false, game, 0)
            end)
        end
        return true
    end

    local last = {}
    local function Cool(k, s)
        local t = os.clock()
        if t - (last[k] or 0) >= s then
            last[k] = t
            return true
        end
        return false
    end

    -- คาดการณ์ตำแหน่งล่วงหน้า (ชดเชย ping) แล้วเช็กว่าอยู่ในโซน Perfect ไหม
    local trk = {}
    local function InWindow(key, v, lo, hi)
        local now = os.clock()
        local t = trk[key]
        local vel = 0
        if t and now > t.t and now - t.t < 0.2 then
            vel = (v - t.v) / (now - t.t)
        end
        trk[key] = { v = v, t = now }
        local p = v + vel * (Config.PerfectLead / 1000)
        return p >= lo and p <= hi
    end

    local function InZone(key, mover, zone, track)
        local vert = track and track.AbsoluteSize.Y > track.AbsoluteSize.X * 1.5
        local a, s, z, zs
        if vert then
            a, s, z, zs = mover.AbsolutePosition.Y, mover.AbsoluteSize.Y, zone.AbsolutePosition.Y, zone.AbsoluteSize.Y
        else
            a, s, z, zs = mover.AbsolutePosition.X, mover.AbsoluteSize.X, zone.AbsolutePosition.X, zone.AbsoluteSize.X
        end
        return InWindow(key, a + s / 2, z, z + zs)
    end

    local function Loop(flag, delay, fn)
        task.spawn(function()
            while true do
                if F[flag] then
                    pcall(fn)
                end
                local d = type(delay) == "number" and delay or Config[delay]
                task.wait(math.max(0.03, tonumber(d) or 1))
            end
        end)
    end

    ------------------------------------------------ 3) เรียนรู้ args จากการที่คุณกดเองในเกม 1 ครั้ง
    local Learn = {}
    local LearnSpec = {
        Pill = { "CultivationService", "RF", "UsePill" },
        Dungeon = { "DungeonService", "RF", "Sweep" },
        Tower = { "TowerService", "RF", "Action" },
    }
    local ByRemote = {}
    for key, s in pairs(LearnSpec) do
        local r = Rm(s[1], s[2], s[3])
        if r then
            ByRemote[r] = key
        end
    end
    if hookmetamethod and getnamecallmethod then
        local old
        old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
            local m = getnamecallmethod()
            if (m == "InvokeServer" or m == "FireServer") and ByRemote[self] and not (checkcaller and checkcaller()) then
                Learn[ByRemote[self]] = { r = self, a = table.pack(...) }
            end
            return old(self, ...)
        end))
    end
    local function Replay(key, label)
        local l = Learn[key]
        if not l then
            if Cool("msg" .. key, 15) then
                Toast("กด " .. label .. " ในเกมเองสักครั้งก่อน เพื่อให้สคริปต์จำค่า")
            end
            return
        end
        Call(l.r, table.unpack(l.a, 1, l.a.n))
    end

    ------------------------------------------------ 4) ลูปฟาร์ม (remote ที่ไม่ต้องใช้ args)
    Loop("AutoAscend", "AscendEvery", function()
        if F.AscendViaUI then
            Press(Find("Root/Content/Ascend/Card/AscendButton"))
        else
            Call(Rm("CultivationService", "RF", "Ascend"))
        end
    end)
    Loop("AutoBreak", "BreakEvery", function()
        Call(Rm("CultivationService", "RF", "BreakthroughMax"))
    end)
    Loop("AutoBuyTech", "BuyEvery", function()
        Call(Rm("CultivationService", "RF", "BuyAllTechniques"))
    end)
    Loop("AutoBooks", "ItemEvery", function()
        Call(Rm("CultivationService", "RF", "UseAllBooks"))
    end)
    Loop("AutoFlesh", "ItemEvery", function()
        Call(Rm("CultivationService", "RF", "RefineFleshMax"))
    end)
    Loop("AutoClaim", "ClaimEvery", function()
        Call(Rm("CultivationService", "RF", "ClaimDaily"))
        Call(Rm("CultivationService", "RF", "ClaimAllGiftOffers"))
        Call(Rm("BattlePassService", "RF", "ClaimAll"))
        Call(Rm("BoostService", "RF", "ClaimHeavenReward"))
    end)
    Loop("AutoPill", "PillEvery", function()
        Replay("Pill", "ใช้ยา")
    end)
    Loop("AutoDungeon", "LearnEvery", function()
        Replay("Dungeon", "Sweep ดันเจี้ยน")
    end)
    Loop("AutoTowerRemote", "LearnEvery", function()
        Replay("Tower", "สู้หอคอย")
    end)

    ------------------------------------------------ 5) ลูปที่ควบคุมผ่าน UI ของเกม
    -- สมาธิ: เปิดหน้า Meditate แล้วกด Hit ตอนเข็มอยู่ใน Core
    Loop("AutoMeditate", 1, function()
        if not Shown(Find("Meditate")) and Cool("medopen", 2) then
            Press(Find("Root/Content/Cultivate/Actions/Meditate"))
        end
    end)

    -- บอสอีเวนต์: เปิด -> เริ่ม -> กดรับผล -> วนใหม่
    Loop("AutoBossFlow", 0.7, function()
        if Shown(Find("BossUI/Result")) then
            local a = Find("BossUI/Result/Action")
            Press(Shown(a) and a or Find("BossUI/Result/Close"))
        elseif Shown(Find("BossUI/Start")) then
            Press(Find("BossUI/Start/Action"))
        elseif not Shown(Find("BossUI/HUD/BossBar")) and Cool("bossopen", 4) then
            Press(Find("Root/Content/Cultivate/BossDock/Button"))
        end
    end)

    -- ตีบอส: แตะ TapZone รัว ๆ
    Loop("AutoBossTap", "TapEvery", function()
        if Shown(Find("BossUI/HUD/BossBar")) and not Shown(Find("BossUI/Result")) then
            Press(Find("BossUI/TapZone"))
        end
    end)

    -- หอคอย: เปิด -> Climb -> เปิด Auto ของเกมตอนเริ่มสู้
    local autoTried = false
    Loop("AutoTower", 1, function()
        if Shown(Find("Tower/FightBar")) then
            local lbl = Find("Tower/FightBar/Auto/Label")
            local txt = lbl and string.lower(lbl.Text) or ""
            if txt:find("off") or txt:find("ปิด") then
                Press(Find("Tower/FightBar/Auto"))
            elseif not (txt:find("on") or txt:find("เปิด")) and not autoTried then
                autoTried = true
                Press(Find("Tower/FightBar/Auto"))
            end
        elseif Shown(Find("Tower/Card")) then
            Press(Find("Tower/Card/Climb"))
        elseif Cool("towopen", 3) then
            Press(Find("Root/Content/Cultivate/TowerDock/Button"))
        end
    end)

    ------------------------------------------------ 6) Perfect timing (ทุกเฟรม)
    local function Tick()
        if F.AutoMeditate and Shown(Find("Meditate")) then
            local needle = Find("Meditate/Track/Groove/Needle")
            local core = Find("Meditate/Track/Groove/Zone/Core")
            local hit = Find("Meditate/Hit")
            if needle and core and hit and InZone("med", needle, core, Find("Meditate/Track")) and Cool("med", 0.35) then
                Press(hit)
            end
        end

        if F.AutoDodgePerfect or F.AutoDodgeSpam then
            local dodge = Find("BossUI/HUD/Dodge")
            if Shown(dodge) then
                local btn = Find("BossUI/HUD/Dodge/Button")
                if F.AutoDodgeSpam and Cool("dspam", 0.03) then
                    Press(btn)
                end
                if F.AutoDodgePerfect then
                    local track = Find("BossUI/HUD/Dodge/Plate/Track")
                    local head = Find("BossUI/HUD/Dodge/Plate/Track/Head")
                    local pass = Find("BossUI/HUD/Dodge/Plate/Track/Pass")
                    if head and pass and InZone("dodge", head, pass, track) and Cool("dperf", 0.25) then
                        Press(btn)
                    end
                end
            end
        end

        if F.AutoPerfectRing and Shown(Find("BossUI/HUD/Ring")) then
            local c = Find("BossUI/HUD/Ring/Closer")
            local t = Find("BossUI/HUD/Ring/Target")
            local p = Find("BossUI/HUD/Ring/Perfect")
            local tap = Find("BossUI/TapZone")
            if c and t and p and tap then
                local a, b = t.AbsoluteSize.X, p.AbsoluteSize.X
                local tol = math.max(a, b) * 0.06
                if InWindow("ring", c.AbsoluteSize.X, math.min(a, b) - tol, math.max(a, b) + tol) and Cool("ring", 0.2) then
                    Press(tap)
                end
            end
        end
    end
    RunService.Heartbeat:Connect(function()
        pcall(Tick)
    end)

    LocalPlayer.Idled:Connect(function()
        if F.AntiAFK then
            pcall(function()
                VU:CaptureController()
                VU:ClickButton2(Vector2.new())
            end)
        end
    end)

    ------------------------------------------------ 7) UI
    local function T(page, key, title, desc)
        Toggle(page, {
            key = key, title = title, desc = desc,
            callback = function(v) F[key] = v end,
        })
    end
    local function S(page, key, title, desc, min, max, step, suffix)
        Slider(page, { key = key, title = title, desc = desc, min = min, max = max, step = step, suffix = suffix })
    end
    local function Btn(page, title, fn)
        local row = Panel(page, UDim2.new(1, 0, 0, 46), "TextButton")
        HoverRow(row)
        Register(row, title)
        local l = Text(row, title, 12, FNT.M, "Text")
        l.Position = UDim2.fromOffset(16, 0)
        l.Size = UDim2.new(1, -32, 1, 0)
        row.MouseButton1Click:Connect(fn)
    end

    local Combat = MakePage("Combat", "บอส & หอคอย", "ตีบอสอีเวนต์  •  หลบ Perfect  •  ปีนหอคอย")
    local Extras = MakePage("Extras", "ไอเท็ม & รางวัล", "ยา  •  ดันเจี้ยน  •  เก็บรางวัล  •  ระบบเสริม")

    -- หน้า ฟังก์ชัน : บำเพ็ญ
    Section(Functions, "บำเพ็ญ / เลื่อนขั้น")
    T(Functions, "AutoAscend", "Auto Ascend", "เลื่อนขั้น Ascend ตามเวลาที่ตั้ง")
    S(Functions, "AscendEvery", "ความถี่ Ascend", "ปรับเวลาได้ (ค่าเริ่มต้น 60 วิ = 1 นาที)", 5, 600, 5, " วิ")
    T(Functions, "AscendViaUI", "Ascend ด้วยปุ่ม UI แทน remote", "เปิดถ้า remote Ascend ไม่ทำงาน (กดปุ่มของเกมแทน)")
    T(Functions, "AutoBreak", "Auto BreakthroughMax", "ทะลวงขั้นสูงสุดอัตโนมัติ")
    S(Functions, "BreakEvery", "ความถี่ Breakthrough", "ค่าเริ่มต้น 0.05 วิ", 0.05, 1, 0.05, " วิ")
    T(Functions, "AutoBuyTech", "Auto Buy All Techniques", "ซื้อเทคนิคทั้งหมดอัตโนมัติ")
    S(Functions, "BuyEvery", "ความถี่ซื้อเทคนิค", "ค่าเริ่มต้น 0.05 วิ", 0.05, 1, 0.05, " วิ")

    Section(Functions, "สมาธิ (Meditate)")
    T(Functions, "AutoMeditate", "Auto Meditate กด Perfect", "เปิดหน้าสมาธิเอง และกดตอนเข็มอยู่กลางโซน")
    S(Functions, "PerfectLead", "ชดเชยเวลากด (Perfect)", "เพิ่มถ้ากดช้าเกิน / ลดถ้ากดเร็วเกิน", 0, 100, 5, " ms")

    -- หน้า บอส & หอคอย
    Section(Combat, "บอสอีเวนต์")
    T(Combat, "AutoBossFlow", "Auto บอสอีเวนต์", "เปิดหน้าบอส > เริ่มสู้ > กดรับผล แล้ววนซ้ำ")
    T(Combat, "AutoBossTap", "Auto ตีบอส", "แตะ TapZone รัว ๆ ระหว่างสู้")
    S(Combat, "TapEvery", "ความถี่ตีบอส", "เวลาระหว่างแต่ละแตะ", 0.05, 1, 0.05, " วิ")
    T(Combat, "AutoPerfectRing", "Perfect Ring ตอนตี", "แตะตอนวงแหวนเข้าโซน Perfect")

    Section(Combat, "หลบบอส")
    T(Combat, "AutoDodgePerfect", "Auto Dodge แบบ Perfect", "กดหลบตอนตัวเลื่อนอยู่ในโซน Pass")
    T(Combat, "AutoDodgeSpam", "Auto Spam Dodge", "รัวปุ่มหลบทุกครั้งที่หน้าหลบโผล่")

    Section(Combat, "หอคอย")
    T(Combat, "AutoTower", "Auto หอคอย", "เปิดหอคอย > Climb > เปิด Auto ของเกม")
    T(Combat, "AutoTowerRemote", "หอคอยแบบ remote (สอน 1 ครั้ง)", "สำรอง: กดสู้หอคอยเองสักครั้งให้สคริปต์จำ")

    -- หน้า ไอเท็ม & รางวัล
    Section(Extras, "ไอเท็ม")
    T(Extras, "AutoPill", "Auto ใช้ยา", "กดใช้ยาในเกมเองสักครั้งให้สคริปต์จำ แล้วใช้ซ้ำให้")
    S(Extras, "PillEvery", "ความถี่ใช้ยา", "เวลาระหว่างแต่ละครั้ง", 1, 60, 1, " วิ")
    T(Extras, "AutoBooks", "Auto ใช้หนังสือทั้งหมด", "UseAllBooks")
    T(Extras, "AutoFlesh", "Auto หลอมร่างกายสูงสุด", "RefineFleshMax")
    S(Extras, "ItemEvery", "ความถี่หนังสือ / หลอมร่าง", "เวลาระหว่างแต่ละครั้ง", 1, 60, 1, " วิ")

    Section(Extras, "ดันเจี้ยน")
    T(Extras, "AutoDungeon", "Auto Sweep ดันเจี้ยน", "กด Sweep ในเกมเองสักครั้งให้สคริปต์จำ")
    S(Extras, "LearnEvery", "ความถี่ดันเจี้ยน / หอคอย remote", "เวลาระหว่างแต่ละครั้ง", 1, 30, 1, " วิ")

    Section(Extras, "รางวัล")
    T(Extras, "AutoClaim", "Auto เก็บรางวัล", "รายวัน / ของขวัญ / Battle Pass / Heaven")
    S(Extras, "ClaimEvery", "ความถี่เก็บรางวัล", "เวลาระหว่างแต่ละรอบ", 5, 300, 5, " วิ")

    Section(Extras, "ระบบเสริม")
    T(Extras, "AntiAFK", "Anti-AFK", "กันหลุดจากการอยู่นิ่ง")
    Btn(Extras, "พิมพ์สถานะ UI ลง Console (Debug)", function()
        for _, k in ipairs({ "Meditate", "BossUI/Start", "BossUI/Result", "BossUI/HUD/BossBar", "BossUI/HUD/Dodge", "BossUI/HUD/Ring", "Tower/Card", "Tower/FightBar" }) do
            local o = Find(k)
            print("[RELWX]", k, o and (Shown(o) and "SHOWN" or "hidden") or "NOT FOUND")
        end
        for k, v in pairs(Learn) do
            print("[RELWX] learned", k, v.a.n .. " args")
        end
        Toast("พิมพ์สถานะลง Console (F9) แล้ว")
    end)

    ------------------------------------------------ 8) แถบเมนูด้านข้าง
    CatGroup("ต่อสู้")
    Category("บอส & หอคอย", "Combat", "grid")
    CatGroup("ไอเท็ม & ระบบ")
    Category("ไอเท็มและรางวัล", "Extras", "sliders")
end)()
