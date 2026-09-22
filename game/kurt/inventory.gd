## Kurt's inventory (`0x57432c`, 5 slots of 0x24 bytes) and sniper ammo (`0x5743f3`), filled by
## the pickups he runs through (`damp_collect_pickups`). See `docs/gameplay.md` ("Pickups").
class_name KurtInventory
extends RefCounted

## Item types of the inventory (by pickup model).
enum Item { NONE, DUMMY, INTERESTING_BOMB, TORNADO, MORTAR, GRENADE, SUPER_CHAIN_GUN, KEY, SEAL, SUPER_BONE }

const ITEM_PICKUPS := {
	"SW_DUMMY": Item.DUMMY,
	"SW_INTER": Item.INTERESTING_BOMB,
	"SW_TWIST": Item.TORNADO,
	"SW_THUMP": Item.MORTAR,
	"SW_HBOMB": Item.GRENADE,
	"SW_GATT": Item.SUPER_CHAIN_GUN,
	"SW_KEY": Item.KEY,
	"SW_SEAL": Item.SEAL,
	"SW_SBONE": Item.SUPER_BONE,
}
## Pickups used at once: sniper ammo (0–4) and health (5–9), 10 and 11 are easter eggs.
const INSTANT_PICKUPS := ["SW_HOME", "SW_SGREN", "SW_HGREN", "SW_LGREN", "SW_BONES", "SW_H25", "SW_H50",
		"SW_H100", "SW_H150", "SW_H01", "SW_EWJ", "BONEFLC"]
## Sniper ammo given by the pickups 0–4 (halved on hard when above 1).
const AMMO_PER_PICKUP := [8, 3, 3, 8, 1]
const MAX_SLOTS := 5
## Per difficulty (easy, normal, hard): grenades per pickup, super chain gun ticks per pickup.
const GRENADES := [5, 3, 1]
const SUPER_CHAIN_GUN_TICKS := [400, 200, 100]


class Slot:
	var item := Item.NONE
	var count := 0


var slots: Array[Slot] = []
var selected := 0
## Sniper ammo per type, and the selected type (1–5, 0 = normal bullets).
var ammo := [0, 0, 0, 0, 0]
var selected_ammo := 0
## Ticks of super chain gun left (`0x5743ef`).
var super_chain_gun := 0
## 0 easy, 1 normal, 2 hard (`0x57423e`).
var difficulty := 1


## Takes a pickup (by model name). Returns the sound to play, or an empty string if Kurt can't
## take it (full inventory, or not a pickup).
func collect(pickup: String, kurt: Kurt) -> String:
	var index := INSTANT_PICKUPS.find(pickup)
	if index >= 0:
		return _use_instant(index, kurt)
	if not ITEM_PICKUPS.has(pickup):
		return ""
	var item: Item = ITEM_PICKUPS[pickup]
	# Grenades and the super chain gun stack in their slot.
	if item in [Item.GRENADE, Item.SUPER_CHAIN_GUN]:
		for i in slots.size():
			if slots[i].item == item:
				_add(slots[i], item)
				if item != Item.SUPER_CHAIN_GUN:
					selected = i
				return "COLLECT"
	if slots.size() >= MAX_SLOTS:
		return ""
	var slot := Slot.new()
	slot.item = item
	if item != Item.SUPER_CHAIN_GUN or slots.is_empty():
		selected = slots.size()
	slots.push_back(slot)
	_add(slot, item)
	return "WMIB" if item == Item.INTERESTING_BOMB else "COLLECT"


func _add(slot: Slot, item: Item) -> void:
	match item:
		Item.GRENADE:
			slot.count += GRENADES[difficulty]
		Item.SUPER_CHAIN_GUN:
			slot.count = 1
			super_chain_gun += SUPER_CHAIN_GUN_TICKS[difficulty]
		_:
			slot.count = 1


func _use_instant(index: int, kurt: Kurt) -> String:
	if index <= 4:
		var amount: int = AMMO_PER_PICKUP[index]
		if difficulty == 2 and amount > 1:
			amount /= 2
		ammo[index] += amount
		selected_ammo = index + 1
		return "BONES" if index == 4 else "COLLECT"
	match index:
		5:
			kurt.health = mini(kurt.health + 10, 100) if kurt.health < 100 else kurt.health
		6:
			kurt.health = mini(kurt.health + 50, 100) if kurt.health < 100 else kurt.health
		7:
			kurt.health = maxi(kurt.health, 100)
		8:
			kurt.health = maxi(kurt.health, 150)
		9:
			kurt.health = mini(kurt.health + 1, 100) if kurt.health < 100 else kurt.health
		10:
			return "COLLECT"
		11:
			return "BONES"
	return "APPLE"


## Removes the super chain gun slot once its time has run out.
func tick_super_chain_gun(ticks: int) -> void:
	if super_chain_gun <= 0:
		return
	super_chain_gun -= ticks
	if super_chain_gun <= 0:
		super_chain_gun = 0
		for i in slots.size():
			if slots[i].item == Item.SUPER_CHAIN_GUN:
				slots.remove_at(i)
				selected = clampi(selected, 0, maxi(slots.size() - 1, 0))
				break
