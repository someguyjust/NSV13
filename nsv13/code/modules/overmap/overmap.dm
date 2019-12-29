#define MASS_TINY 1
#define MASS_SMALL 2
#define MASS_MEDIUM 3
#define MASS_LARGE 4
#define MASS_TITAN 5

/////////////////////////////////////////////////////////////////////////////////
// ACKNOWLEDGEMENTS:  Credit to yogstation (Monster860) for the movement code. //
// I had no part in writing the movement engine, that's his work               //
/////////////////////////////////////////////////////////////////////////////////

/mob
	var/obj/structure/overmap/overmap_ship //Used for relaying movement, hotkeys etc.

/obj/structure/overmap
	name = "overmap ship"
	desc = "A space faring vessel."
	icon = 'nsv13/icons/overmap/default.dmi'
	icon_state = "default"
	density = TRUE
	dir = NORTH
	layer = HIGH_OBJ_LAYER
	bound_width = 64 //Change this on a per ship basis
	bound_height = 64
	animate_movement = NO_STEPS // Override the inbuilt movement engine to avoid bouncing
	req_one_access = list(ACCESS_HEADS, ACCESS_MUNITIONS, ACCESS_SEC_DOORS, ACCESS_ENGINE) //Bridge officers/heads, munitions techs / fighter pilots, security officers, engineering personnel all have access.

	anchored = FALSE
	resistance_flags = LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF // Overmap ships represent massive craft that don't burn

	max_integrity = 300 //Max health
	integrity_failure = 0

	var/next_firetime = 0
	var/last_slowprocess = 0
	var/mob/living/pilot //Physical mob that's piloting us. Cameras come later

	//Movement Variables

	var/velocity_x = 0 // tiles per second.
	var/velocity_y = 0
	var/offset_x = 0 // like pixel_x/y but in tiles
	var/offset_y = 0
	var/angle = 0 // degrees, clockwise
	var/desired_angle = null // set by pilot moving his mouse
	var/angular_velocity = 0 // degrees per second
	var/max_angular_acceleration = 180 // in degrees per second per second
	var/speed_limit = 5 //Stops ships from going too damn fast. This can be overridden by things like fighters launching from tubes, so it's not a const.
	var/last_thrust_forward = 0
	var/last_thrust_right = 0
	var/last_rotate = 0

	var/user_thrust_dir = 0

	//Movement speed variables

	var/forward_maxthrust = 6
	var/backward_maxthrust = 3
	var/side_maxthrust = 1
	var/mass = MASS_SMALL //The "mass" variable will scale the movespeed according to how large the ship is.

	var/bump_impulse = 0.6
	var/bounce_factor = 0.2 // how much of our velocity to keep on collision
	var/lateral_bounce_factor = 0.95 // mostly there to slow you down when you drive (pilot?) down a 2x2 corridor
	var/brakes = FALSE //Helps you stop the ship
	var/fire_delay = 5
	var/weapon_range = 10 //Range changes based on what weapon youre using.
	var/obj/railgun_overlay/railgun_overlay
	var/atom/last_target //Last thing we shot at, used to point the railgun at an enemy.
	var/rcs_mode = FALSE //stops you from swivelling on mouse move
	var/fire_mode = FIRE_MODE_PDC //What gun do we want to fire? Defaults to railgun, with PDCs there for flak
	var/move_by_mouse = TRUE //It's way easier this way, but people can choose.
	var/faction = null //Used for target acquisition by AIs
	var/sprite_size = 64 //Pixels. This represents 64x64 and allows for the bullets that you fire to align properly.
	var/torpedoes = 15 //Prevent infinite torp spam
	var/pdc_miss_chance = 20 //In %, how often do PDCs fire inaccurately when aiming at missiles. This is ignored for ships as theyre bigger targets.
	var/list/dent_decals = list() //Ships get visibly damaged as they get shot
	var/damage_states = FALSE //Did you sprite damage states for this ship? If yes, set this to true
	var/list/torpedoes_to_target = list() //Torpedoes that have been fired explicitly at us, and that the PDCs need to worry about.
	var/main_overmap = FALSE //There can only be one of these per game! This denotes that this ship is the "hero ship" and what the players fly. This links it to all the station areas by default
	var/area_type = null //Set the type of the desired area you want a ship to link to, assuming it's not the main player ship.
	var/area/linked_area = null //The area to which we're linked. This is for Ai / small ships only.
	var/list/mobs_in_ship = list() //A list of mobs which is inside the ship. This is generated by our areas.dm file as they enter / exit areas
	var/impact_sound_cooldown = FALSE //Avoids infinite spamming of the ship taking damage.
	var/mob/living/gunner //The person who fires the guns.
	var/list/operators = list() //Everyone who needs their client updating when we move.
	var/obj/machinery/computer/ship/helm //Relay beeping noises when we act
	var/obj/machinery/computer/ship/tactical
	var/obj/machinery/computer/ship/dradis/dradis //So that pilots can check the radar easily
	var/list/railguns = list() //Every railgun present on the ship
	var/list/torpedo_tubes = list() //every torpedo tube present on the ship.
	var/list/pdcs = list() //Every PDC ammo rack that we have.
	var/datum/starsystem/current_system //What starsystem are we currently in? Used for parallax.
	var/datum/gas_mixture/cabin_air //Cabin air mix used for small ships like fighters (see overmap/fighters/fighters.dm)
	var/obj/machinery/portable_atmospherics/canister/internal_tank //Internal air tank reference. Used mostly in small ships. If you want to sabotage a fighter, load a plasma tank into its cockpit :)
	var/resize = 0 //Factor by which we should shrink a ship down. 0 means don't shrink it.
	var/list/docking_points = list() //Where we can land on this ship. Usually right at the edge of a z-level.
	var/weapon_safety = FALSE //Like a gun safety. Entirely un-used except for fighters to stop brainlets from shooting people on the ship unintentionally :)
	var/armour_plates = 0 //You lose max integrity when you lose armour plates.
	var/max_armour_plates = 500 //Placeholder. Set by counting in game objects.

/obj/structure/overmap/can_be_pulled(user) // no :)
	return FALSE

/obj/railgun_overlay //Railgun sits on top of the ship and swivels to face its target
	name = "Railgun"
	icon_state = "railgun"
	layer = 4
	mouse_opacity = FALSE
	var/angle = 0 //Debug

/obj/structure/overmap/Initialize()
	. = ..()
	GLOB.overmap_objects += src
	START_PROCESSING(SSovermap, src)
	railgun_overlay = new()
	railgun_overlay.appearance_flags |= KEEP_APART
	railgun_overlay.appearance_flags |= RESET_TRANSFORM
	vis_contents += railgun_overlay
	update_icon()
	max_range = initial(weapon_range)+20 //Range of the maximum possible attack (torpedo)
	find_area()
	switch(mass) //Scale speed with mass (tonnage)
		if(MASS_TINY) //Tiny ships are manned by people, so they need air.
			forward_maxthrust = 4
			backward_maxthrust = 4
			side_maxthrust = 3
			max_angular_acceleration = 180
			cabin_air = new
			cabin_air.temperature = T20C
			cabin_air.volume = 200
			cabin_air.add_gases(/datum/gas/oxygen, /datum/gas/nitrogen)
			cabin_air.gases[/datum/gas/oxygen][MOLES] = O2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
			cabin_air.gases[/datum/gas/nitrogen][MOLES] = N2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
		if(MASS_SMALL)
			forward_maxthrust = 3
			backward_maxthrust = 3
			side_maxthrust = 2
			max_angular_acceleration = 110
		if(MASS_MEDIUM)
			forward_maxthrust = 2
			backward_maxthrust = 1
			side_maxthrust = 1
			max_angular_acceleration = 120
		if(MASS_LARGE)
			forward_maxthrust = 0.3
			backward_maxthrust = 0.3
			side_maxthrust = 0.2
			max_angular_acceleration = 15
		if(MASS_TITAN)
			forward_maxthrust = 0.1
			backward_maxthrust = 0.1
			side_maxthrust = 0.1
			max_angular_acceleration = 5
	if(main_overmap)
		name = "[station_name()]"
	current_system = GLOB.starsystem_controller.find_system(src)
	addtimer(CALLBACK(src, .proc/check_armour), 20 SECONDS)

/obj/structure/overmap/Destroy()
	if(cabin_air)
		QDEL_NULL(cabin_air)
	. = ..()

/obj/structure/overmap/proc/find_area()
	if(main_overmap) //We're the hero ship, link us to every ss13 area.
		for(var/X in GLOB.teleportlocs) //Teleportlocs = ss13 areas that aren't special / centcom
			var/area/area = GLOB.teleportlocs[X] //Pick a station area and yeet it.
			area.linked_overmap = src
	for(var/area/AR in GLOB.sortedAreas) //Otherwise, look for an area with the same "class" var as us.
		if(!area_type) //No area type set? Break the loop.
			return
		if(istype(AR, area_type))
			AR.linked_overmap = src
			linked_area = AR

/obj/structure/overmap/proc/InterceptClickOn(mob/user, params, atom/target)
	var/list/params_list = params2list(params)
	if(user.incapacitated() || !isliving(user))
		return FALSE
	if(target == src || istype(target, /obj/screen) || (target && (target in user.GetAllContents())) || user != gunner || params_list["shift"] || params_list["alt"] || params_list["ctrl"])
		return FALSE
	if(tactical && prob(80))
		var/sound = pick(GLOB.computer_beeps)
		playsound(tactical, sound, 100, 1)
	fire(target)
	return TRUE

/obj/structure/overmap/onMouseMove(object,location,control,params)
	if(!pilot || !pilot.client || pilot.incapacitated() || !move_by_mouse || control !="mapwindow.map") //Check pilot status, if we're meant to follow the mouse, and if theyre actually moving over a tile rather than in a menu
		return // I don't know what's going on.
	var/list/params_list = params2list(params)
	var/sl_list = splittext(params_list["screen-loc"],",")
	var/sl_x_list = splittext(sl_list[1], ":")
	var/sl_y_list = splittext(sl_list[2], ":")
	var/view_list = isnum(pilot.client.view) ? list("[pilot.client.view*2+1]","[pilot.client.view*2+1]") : splittext(pilot.client.view, "x")
	var/dx = text2num(sl_x_list[1]) + (text2num(sl_x_list[2]) / world.icon_size) - 1 - text2num(view_list[1]) / 2
	var/dy = text2num(sl_y_list[1]) + (text2num(sl_y_list[2]) / world.icon_size) - 1 - text2num(view_list[2]) / 2
	if(sqrt(dx*dx+dy*dy) > 1)
		desired_angle = 90 - ATAN2(dx, dy)
	else
		desired_angle = null

/obj/structure/overmap/take_damage()
	..()
	if(!impact_sound_cooldown)
		var/sound = pick(GLOB.overmap_impact_sounds)
		relay(sound)
		shake_everyone(5)
		impact_sound_cooldown = TRUE
		addtimer(VARSET_CALLBACK(src, impact_sound_cooldown, FALSE), 10)
	update_icon()

/obj/structure/overmap/relaymove(mob/user, direction)
	if(user != pilot || pilot.incapacitated() || !can_move())
		return
	if(rcs_mode || move_by_mouse) //They don't want to turn the ship, or theyre using mouse movement mode.
		user_thrust_dir = direction
	else
		switch(direction)
			if(NORTH || SOUTH || NORTHEAST || SOUTHEAST || NORTHWEST || SOUTHWEST) //Forward or backwards means we don't want to turn
				user_thrust_dir = direction
			if(EAST) //Left or right means we do want to turn
				desired_angle += max_angular_acceleration*0.1
			if(WEST)
				desired_angle -= max_angular_acceleration*0.1

/obj/structure/overmap/proc/can_move()
	return TRUE//Used mostly for fighters. If we ever get engines, change this.

//	relay('nsv13/sound/effects/ship/rcs.ogg')

/obj/structure/overmap/update_icon() //Adds an rcs overlay
	cut_overlays()
	apply_damage_states()
	if(railgun_overlay) //Swivel the railgun to aim at the last thing we hit
		railgun_overlay.icon = icon
		railgun_overlay.setDir(get_dir(src, last_target))
	if(angle == desired_angle)
		return //No RCS needed if we're already facing where we want to go
	if(prob(20) && desired_angle)
		playsound(src, 'nsv13/sound/effects/ship/rcs.ogg', 30, 1)
	var/list/left_thrusts = list()
	left_thrusts.len = 8
	var/list/right_thrusts = list()
	right_thrusts.len = 8
	var/back_thrust = 0
	for(var/cdir in GLOB.cardinals)
		left_thrusts[cdir] = 0
		right_thrusts[cdir] = 0
	if(last_thrust_right != 0)
		var/tdir = last_thrust_right > 0 ? WEST : EAST
		left_thrusts[tdir] = abs(last_thrust_right) / side_maxthrust
		right_thrusts[tdir] = abs(last_thrust_right) / side_maxthrust
	if(last_thrust_forward > 0)
		back_thrust = last_thrust_forward / forward_maxthrust
	if(last_thrust_forward < 0)
		left_thrusts[NORTH] = -last_thrust_forward / backward_maxthrust
		right_thrusts[NORTH] = -last_thrust_forward / backward_maxthrust
	if(last_rotate != 0)
		var/frac = abs(last_rotate) / max_angular_acceleration
		for(var/cdir in GLOB.cardinals)
			if(last_rotate > 0)
				right_thrusts[cdir] += frac
			else
				left_thrusts[cdir] += frac
	for(var/cdir in GLOB.cardinals)
		var/left_thrust = left_thrusts[cdir]
		var/right_thrust = right_thrusts[cdir]
		if(left_thrust)
			add_overlay(image(icon = icon, icon_state = "rcs_left", dir = cdir))
		if(right_thrust)
			add_overlay(image(icon = icon, icon_state = "rcs_right", dir = cdir))
	if(back_thrust)
		var/image/I = image(icon = icon, icon_state = "thrust")
		add_overlay(I)

/obj/structure/overmap/proc/apply_damage_states()
	if(!damage_states)
		return
	var/progress = obj_integrity //How damaged is this shield? We examine the position of index "I" in the for loop to check which directional we want to check
	var/goal = max_integrity //How much is the max hp of the shield? This is constant through all of them
	progress = CLAMP(progress, 0, goal)
	progress = round(((progress / goal) * 100), 25)//Round it down to 20%. We now apply visual damage
	icon_state = "[initial(icon_state)]-[progress]"

/obj/structure/overmap/proc/relay(var/sound, var/message=null, loop = FALSE, channel = null) //Sends a sound + text message to the crew of a ship
	for(var/X in mobs_in_ship)
		if(ismob(X))
			var/mob/mob = X
			if(sound)
				if(channel) //Doing this forbids overlapping of sounds
					SEND_SOUND(mob, sound(sound, repeat = loop, wait = 0, volume = 100, channel = channel))
				else
					SEND_SOUND(mob, sound(sound, repeat = loop, wait = 0, volume = 100))
			if(message)
				to_chat(mob, message)

/obj/structure/overmap/proc/stop_relay(channel) //Stops all playing sounds for crewmen on N channel.
	for(var/X in mobs_in_ship)
		if(ismob(X))
			var/mob/mob = X
			mob.stop_sound_channel(channel)

/obj/structure/overmap/proc/relay_to_nearby(sound, message, ignore_self=FALSE) //Sends a sound + text message to nearby ships
	for(var/obj/structure/overmap/ship in GLOB.overmap_objects)
		if(ignore_self)
			if(ship == src)
				continue
		if(get_dist(src, ship) <= 20) //Sound doesnt really travel in space, but space combat with no kaboom is LAME
			ship.relay(sound,message)
	for(var/Y in GLOB.dead_mob_list)
		var/mob/dead/M = Y
		if(M.z == z) //Ghosts get to hear explosions too for clout.
			SEND_SOUND(M,sound)

/obj/structure/overmap/proc/verb_check(require_pilot = TRUE, mob/user = null)
	if(!user)
		user = usr
	if(user != pilot)
		to_chat(user, "<span class='notice'>You can't reach the controls from here</span>")
		return FALSE
	return !user.incapacitated() && isliving(user)

/obj/structure/overmap/key_down(key, client/user)
	var/mob/themob = user.mob
	switch(key)
		if("Space")
			if(themob == pilot)
				toggle_move_mode()
			if(helm && prob(80))
				var/sound = pick(GLOB.computer_beeps)
				playsound(helm, sound, 100, 1)
			return TRUE
		if("Alt")
			if(themob == pilot)
				toggle_brakes()
			if(helm && prob(80))
				var/sound = pick(GLOB.computer_beeps)
				playsound(helm, sound, 100, 1)
			return TRUE
		if("Ctrl")
			if(themob == gunner)
				cycle_firemode()
			if(tactical && prob(80))
				var/sound = pick(GLOB.computer_beeps)
				playsound(tactical, sound, 100, 1)
			return TRUE
	return FALSE

/obj/structure/overmap/verb/toggle_brakes()
	set name = "Toggle Handbrake"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check() || !can_brake())
		return
	brakes = !brakes
	to_chat(usr, "<span class='notice'>You toggle the brakes [brakes ? "on" : "off"].</span>")

/obj/structure/overmap/verb/toggle_safety()
	set name = "Toggle Gun Safeties"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check() || !can_brake())
		return
	weapon_safety = !weapon_safety
	to_chat(usr, "<span class='notice'>You toggle [src]'s weapon safeties [weapon_safety ? "on" : "off"].</span>")

/obj/structure/overmap/verb/show_dradis()
	set name = "Show DRADIS"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check() || !dradis)
		return
	dradis.attack_hand(usr)

/obj/structure/overmap/proc/can_brake()
	return TRUE //See fighters.dm

/obj/structure/overmap/verb/overmap_help()
	set name = "Help"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check())
		return
	to_chat(usr, "<span class='warning'>=Hotkeys=</span>")
	to_chat(usr, "<span class='notice'>Use the <b>scroll wheel</b> to zoom in / out.</span>")
	to_chat(usr, "<span class='notice'>Use tab to activate hotkey mode, then:</span>")
	to_chat(usr, "<span class='notice'>Press <b>space</b> to make the ship follow your mouse (or stop following your mouse).</span>")
	to_chat(usr, "<span class='notice'>Press <b>Alt<b> to engage handbrake</span>")
	to_chat(usr, "<span class='notice'>Press <b>Ctrl<b> to cycle fire modes</span>")

/obj/structure/overmap/verb/toggle_move_mode()
	set name = "Change movement mode"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check())
		return
	move_by_mouse = !move_by_mouse
	to_chat(usr, "<span class='notice'>You [move_by_mouse ? "activate" : "deactivate"] [src]'s laser guided movement system.</span>")

