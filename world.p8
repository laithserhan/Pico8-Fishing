pico-8 cartridge // http://www.pico-8.com
version 18
__lua__

-- Basic Fishing Prototype --

debug = false
currentroom = nil
entities = {}
rooms = {}

------------------------- UTILS ---------------------------
function ternary(cond, t, f)
  if cond then return t else return f end
end

function sort(list, comparator)
  -- insertion sort
  for i = 2, #list do
    local j = i
    while j > 1 and comparator(list[j-1], list[j]) do
      list[j], list[j-1] = list[j-1], list[j]
      j -= 1
    end
  end
end

function ycomparator(a, b)
  if a.pos == nil or b.pos == nil then return false end
  return a.pos.y + a.pos.h > b.pos.y + b.pos.h
end

function debugcollider(pos, c, color)
  rect(pos.x + c.xoff, pos.y + c.yoff,
    pos.x + c.xoff + c.w - 1, pos.y + c.yoff + c.h - 1, color)
end

function debugprint(txt, e)
  if debug and e then
    print(txt, e.pos.x, e.pos.y+10, 7) 
  end
end

function maskoutside(camx, camy)
  rectfill(-1, -1, 128, (currentroom.y*8)-camy-1, currentroom.bg)
  rectfill(-1, -1, (currentroom.x*8)-camx-1, 128, currentroom.bg)
  rectfill(((currentroom.x + currentroom.w)*8)-camx, -1, 128, 128, currentroom.bg)
  rectfill(-1, ((currentroom.y + currentroom.h)*8)-camy, 128, 128, currentroom.bg)
end

function drawtext(text, x, y, color, outline)
  for i=-1,1 do 
    for j=-1,1 do 
      print(text, x + i, y + j, outline) 
    end
  end
  print(text, x, y, color)
end

function tablecontains(table, val)
  for i=1, #table do
    if table[i] == val then return true end
  end
  return false
end

function newroom(x, y, w, h, bg)
  local r = {}
  r.x, r.y, r.w, r.h, r.bg = x, y, w, h, bg
  return r
end

------------------------- SYSTEMS -------------------------
gfxsys = {}
gfxsys.update = function()
  local camx = -64 + player.pos.x + (player.pos.w / 2)
  local camy = -64 + player.pos.y + (player.pos.h / 2)
  cls()
  sort(entities, ycomparator)
  camera(camx, camy)
  map()
  for e in all(entities) do
    if e.sprite then
      if e.intent then
        if e.intent.left  then e.sprite.isflipped = true end
        if e.intent.right then e.sprite.isflipped = false end
      end
      if e.pos then
        sspr(
          e.sprite.spritelist[e.sprite.index][1], 
          e.sprite.spritelist[e.sprite.index][2],
          e.pos.w, e.pos.h, e.pos.x, e.pos.y, e.pos.w, e.pos.h,
          e.sprite.isflipped, false
        )
      end
    end
    if debug and e.pos then
      if e.bounds and e.id ~= player.id then 
        debugcollider(e.pos, e.bounds, 9)  
      end
      if e.trigger then
        debugcollider(e.pos, e.trigger, ternary(e.trigger.isactive, 11, 8)) 
      end
    end
  end
  camera()
  maskoutside(camx, camy)
  camera(camx, camy)
  for e in all(entities) do
    if e.pos and e.dialog and e.dialog.text and ((not e.dialog.istimed) or (e.dialog.istimed and e.dialog.time > 0)) then
      local subtext = sub(e.dialog.text, 0, e.dialog.cursor)
      drawtext(subtext, e.pos.x-10, e.pos.y-10, 7, 0)
    end
  end
end

ctrlsys = {}
ctrlsys.update = function()
  for e in all(entities) do
    if e.control and e.intent then
      e.control.input(e)
    end
  end
end

physys = {}
physys.update = function()
  for e in all(entities) do
    local newx = e.pos.x
    local newy = e.pos.y
    local canmovex = true
    local canmovey = true

    if e.pos then
      if e.intent then
        if e.intent.left  then newx -= 1 end
        if e.intent.right then newx += 1 end
        if e.intent.up    then newy -= 1 end
        if e.intent.down  then newy += 1 end
      end
      if e.bounds then
        if not canmove(newx, e.pos.y, e.bounds) then canmovex = false end
        if not canmove(e.pos.x, newy, e.bounds) then canmovey = false end
        for o in all(entities) do
          if o ~= e and o.pos and o.bounds then
            if hascollidedx(newx, e.pos, o.pos, e.bounds, o.bounds) then
              canmovex = false
            end
            if hascollidedy(newy, e.pos, o.pos, e.bounds, o.bounds) then
              canmovey = false
            end
          end
        end
      end
    end
    e.pos.x = ternary(canmovex, newx, e.pos.x)
    e.pos.y = ternary(canmovey, newy, e.pos.y)
  end
end

animsys = {}
animsys.update = function()
  for e in all(entities) do
    if e.sprite and e.anim then
      if e.anim.type == 'continuous' or 
      (e.intent and e.anim.type == 'walk' and e.intent.ismoving) then
        e.anim.timer += 1
        if e.anim.timer > e.anim.delay then
          e.sprite.index += 1
          if e.sprite.index > #e.sprite.spritelist then
            e.sprite.index = 1
          end
          e.anim.timer = 0
        end
      else
        e.sprite.index = 1
      end
    end
  end
end

triggsys = {}
triggsys.update = function()
  for e in all(entities) do
    if e.trigger and e.pos then
      local istriggered = false
      for o in all(entities) do
        if o ~= e and o.bounds and o.pos and (
         hascollidedx(e.pos.x, e.pos, o.pos, e.trigger, o.bounds) or 
         hascollidedy(e.pos.y, e.pos, o.pos, e.trigger, o.bounds)
        ) then
          istriggered = true
          if e.trigger.type == 'once' then
            e.trigger.f(e, o)
            e.trigger = nil
            break
          elseif e.trigger.type == 'yield' and not e.trigger.isactive then
            e.trigger.f(e, o)
            e.trigger.isactive = true
          elseif e.trigger.type == 'continuous' then
            e.trigger.f(e, o)
          end
        end
      end
      e.trigger.isactive = istriggered
    end
  end
end

dialogsys = {}
dialogsys.update = function()
  for e in all(entities) do
    if e.dialog and e.dialog.text then 
      if e.dialog.cursor < #e.dialog.text then
        e.dialog.cursor += 1
      end
      if e.dialog.istimed and e.dialog.time > 0 then
        e.dialog.time -= 1
      end
    end
  end
end

------------------------- ENTITIES ------------------------
function newentity(components)
  local e = {}
  e.id = #entities+1
  e.pos = components.pos
  e.sprite = components.sprite
  e.control = components.control
  e.intent = components.intent
  e.bounds = components.bounds
  e.anim = components.anim
  e.trigger = components.trigger
  e.dialog = components.dialog
  return e
end

function playerinput(e)
  e.intent.left  = btn(e.control.left)
  e.intent.right = btn(e.control.right)
  e.intent.up    = btn(e.control.up)
  e.intent.down  = btn(e.control.down)
  e.intent.ismoving = e.intent.left or e.intent.right or e.intent.up or e.intent.down
end

function canmove(x, y, coll)
  local xoff, yoff = x + coll.xoff, y + coll.yoff
  return (not fget(mget(xoff / 8, yoff / 8), 7)) and
    (not fget(mget((xoff + coll.w-1) / 8, (yoff + coll.h-1) / 8), 7))
end

function hascollided(x1, y1, w1, h1, x2, y2, w2, h2)
  return (x1 + w1 > x2) and (x1 < x2 + w2) and (y1 + h1 > y2) and (y1 < y2 + h2)
end

function hascollidedx(newx, pos1, pos2, coll1, coll2)
  return hascollided(
    newx + coll1.xoff, pos1.y + coll1.yoff, coll1.w, coll1.h, 
    pos2.x + coll2.xoff, pos2.y + coll2.yoff, coll2.w, coll2.h)
end

function hascollidedy(newy, pos1, pos2, coll1, coll2)
  return hascollided(
    pos1.x + coll1.xoff, newy + coll1.yoff, coll1.w, coll1.h,
    pos2.x + coll2.xoff, pos2.y + coll2.yoff, coll2.w, coll2.h)
end

function newentitybubbles(x, y)
  return newentity({
    pos = positioncomponent(x, y, 8, 8),
    sprite = spritecomponent({{64, 24}, {72, 24}}, 1),
    bounds = boundscomponent(0, 0, 8, 8),
    anim = animationcomponent(25, 'continuous')
  })
end

function newentitytext(x, y, txt)
  return newentity({
    pos = positioncomponent(x, y, 8, 8),
    trigger = triggercomponent(4, 10, 8, 8, function(self, other)
      if other == player then other.dialog.set(txt, true) end
    end, 'yield')
  })
end


------------------------ COMPONENTS -----------------------
function spritecomponent(spritelist, idx)
  local s = {}
  s.spritelist, s.index, isflipped = spritelist, idx, false
  return s
end

function positioncomponent(x, y, w, h)
  local p = {}
  p.x, p.y, p.w, p.h = x, y, w, h
  return p
end

function boundscomponent(xoff, yoff, w, h)
  local b = {}
  b.xoff, b.yoff, b.w, b.h = xoff, yoff, w, h
  return b
end

function controlcomponent(left, right, up, down, input)
  local c = {}
  c.left, c.right, c.up, c.down, c.input = left, right, up, down, input
  return c
end

function intentioncomponent()
  local i = {}
  i.left, i.right, i.up, i.down, i.ismoving = false
  return i
end

function animationcomponent(d, t)
  local a = {}
  a.timer, a.delay, a.type = 0, d, t
  return a
end

function triggercomponent(xoff, yoff, w, h, f, type)
  local t = {}
  t.xoff, t.yoff, t.w, t.h, t.f = xoff, yoff, w, h, f
  assert(tablecontains({'single', 'continuous', 'yield'}, type), "Invalid trigger type")
  t.type, t.isactive = type, false
  return t
end

function dialogcomponent()
  local d = {}
  d.text, d.istimed, d.time, d.cursor = nil, false, 0, 0
  d.set = function(txt, timed)
    d.text, d.istimed = txt, timed
    d.cursor = 0
    if timed then d.time = 30 end
  end
  return d
end

--------------------------- MAIN --------------------------
function initrooms()
  rooms.outside = newroom(2, 2, 22, 12, 3)
  rooms.building = newroom(27, 2, 19, 12, 0) 
end

function initentities()
  player = newentity({
    pos = positioncomponent(30, 30, 4, 8),
    sprite = spritecomponent({{8, 0}, {12, 0}, {16, 0}, {20, 0}}, 1),
    control = controlcomponent(0, 1, 2, 3, playerinput),
    intent = intentioncomponent(),
    bounds = boundscomponent(0, 6, 4, 2),
    anim = animationcomponent(4, 'walk'),
    dialog = dialogcomponent()
  })
  add(entities, player)

  -- bubbles
  add(entities, newentitybubbles(128, 48))
  add(entities, newentitybubbles(128, 64))
  add(entities, newentitybubbles(136, 48))
  add(entities, newentitybubbles(136, 40))
  add(entities, newentitybubbles(136, 72))
  add(entities, newentitybubbles(152, 80))
  add(entities, newentitybubbles(160, 56))

  -- tree
  add(entities, newentity({
    pos = positioncomponent(50, 50, 16, 16),
    sprite = spritecomponent({{8, 8}}, 1),
    bounds = boundscomponent(6, 12, 4, 5),
    trigger = triggercomponent(4, 10, 8, 8, function(self, other)
      if other == player then 
        other.dialog.set('hello tree', true)
      end
    end, 'yield')
  }))

  -- building
  add(entities, newentity({
    pos = positioncomponent(70, 40, 16, 16),
    sprite = spritecomponent({{48, 16}}, 1),
    bounds = boundscomponent(0, 8, 16, 8),
    trigger = triggercomponent(10, 16, 4, 3, function(self, other)
      if other == player then 
        other.pos.x, other.pos.y = 340, 90 
        currentroom = rooms.building
      end
    end, 'continuous')
  }))
  add(entities, newentity({
    pos = positioncomponent(336, 105, 16, 3),
    trigger = triggercomponent(0, 0, 16, 3, function(self, other)
      if other == player then 
        other.pos.x, other.pos.y = 80, 60
        currentroom = rooms.outside
      end
    end, 'continuous')
  }))
  add(entities, newentitytext(336, 84, 'nothing here yet :)'))
end

function _init()
  initrooms()
  initentities()
  currentroom = rooms.outside
end

function _update()
  ctrlsys.update()
  physys.update()
  animsys.update()
  triggsys.update()
  dialogsys.update()
end

function _draw()
  gfxsys.update()
end


__gfx__
00000000444444444444444400000000000000000000000000000000000000000000000033333333cccccccc3333cccccccc3333333443333334433333333333
000000004f3f4f3f4f3f4f3f00000000000000000000000000000000000000000000000033333333cccccccc33cccccccccccc33333443333334433333333333
00700700ffffffffffffffff00000000000000000000000000000000000000000000000033333333cccccccc3cccccccccccccc3334444333344443333444433
00077000888888888888888800000000000000000000000000000000000000000000000033333333cccccccc3cccccccccccccc3334554334445543344455433
000770008f858f858f858f8500000000000000000000000000000000000000000000000033333333cccccccccccccccccccccccc334554334445543344455433
007007008f8588f58f85f88500000000000000000000000000000000000000000000000033333333cccccccccccccccccccccccc334444333344443333444433
00000000888888888888888800000000000000000000000000000000000000000000000033333333cccccccccccccccccccccccc333443333333333333344333
00000000011010100100001000000000000000000000000000000000000000000000000033333333cccccccccccccccccccccccc333443333333333333344333
00000000000000bbbb0000000000000000000000000000000000000033333333000000003333333300000000cccccccccccccccc333333333333333333344333
00000000000bbbbbbbb000000000000000000000000000000000000033b33333000000003339333300000000cccccccccccccccc333333333333333333344333
00000000000bbbbbbbbb00000000000000000000000000000000000033333333000000003333333300000000cccccccccccccccc334444333344443333444433
0000000000bbbbbbbbbbb0000000000000000000000000000000000033333b33000000003a3333a300000000cccccccccccccccc444554443345544433455444
000000000bbb4bb4bbbbbb00000000000000000000000000000000003b3333330000000033337333000000003cccccccccccccc3444554443345544433455444
000000000bbb4bb4bbbbbb0000000000000000000000000000000000333333330000000033377733000000003cccccccccccccc3334444333344443333444433
000000000bbbb4b44bbbbb000000000000000000000000000000000033b333b300000000333373330000000033cccccccccccc33333333333334433333333333
0000000000bbb40b4bb4bb0000000000000000000000000000000000333333330000000033333333000000003333cccccccc3333333333333334433333333333
00000000000bb400404bb00000000000000000000000000057777777777777770000000000000000000000003333333333333333000000004444444455655555
000000000000bb444040000000000000000000000000000057555555555555570000000000000000000000003333333333333333000000004444444455655555
00000000000000044400000000000000000000000000000057666666666666570000000000000000000000003333333333333333000000004444444455655555
00000000000004044000000000000000000000000000000057666666666666570000000000000000000000003333333333333333000000000000000066666666
0000000000000044400000000000000000000000000000005766666666666657000000000000000000000000c33333333333333c000000000000000055555655
0000000000000004400000000000000000000000000000005766666666666657000000000000000000000000c33333333333333c000000000000000055555655
0000000000000004400000000000000000000000000000005777777777777777000000000000000000000000cc333333333333cc000000000000000055555655
0000000000000004400000000000000000000000000000005666666666666667000000000000000000000000cccc33333333cccc000000000000000066666666
cccccccc00000000000000000000000000000000000000005666666666666667cccccccccccccccc00000000cccc33333333cccc000000000000000066776677
45454545000000000000000000000000000000000000000056cccccc66666667cc7cccccc7cc7ccc00000000cc333333333333cc000000000000000066776677
54545454000000000000000000000000000000000000000056ccc7cc66666667c7c7cccccccccccc00000000c33333333333333c000000000000000077667766
54545454000000000000000000000000000000000000000056cc7ccc66444467cccccc7cccccc7cc00000000c33333333333333c000000000000000077667766
54545454000000000000000000000000000000000000000056cccccc66444467cccccccccccc7c7c000000003333333333333333000000000000000066776677
5454545400000000000000000000000000000000000000005666666666444467cccc7ccccc7ccccc000000003333333333333333000000000000000066776677
5454545400000000000000000000000000000000000000005666666666444467ccc7c7cccccc7ccc000000003333333333333333000000000000000077667766
4545454500000000000000000000000000000000000000005666666666444467cccccccccccccccc000000003333333333333333000000000000000077667766
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2e2e2f2f2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000080808080808000000000000000000000008080808080000000000000000000000000000000800000000000000000808000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00001e1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d0f0000002f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d09090909090909090909090909090909091909090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d0909090917190909090909092c0b0a0c090919090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d0909090919090919090909090b0a1a0a090909090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d0917090909090909090909090a1a1a0a2b0909090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d09090909090909091709090930300a0a0a000c090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d0909090909090909090909090a000a0a0a0a0a090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d0909170917090909090909091b0a1a0a0a0a0a090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d0919090909090909090909093c1b0a0a000a1c090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d09090909090909090909190909090909090909090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d09190909090909091909090909090917090909090d0000002f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00001f1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d0e0000002f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2e2e2f2f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
