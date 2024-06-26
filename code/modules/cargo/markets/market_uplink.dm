/obj/item/market_uplink
	name = "\improper Market Uplink"
	desc = "An market uplink. Usable with markets. You probably shouldn't have this!"
	icon = 'icons/obj/blackmarket.dmi'
	icon_state = "uplink"

	// UI variables.
	/// What category is the current uplink viewing?
	var/viewing_category
	/// What market is currently being bought from by the uplink?
	var/viewing_market
	/// What item is the current uplink attempting to buy?
	var/selected_item
	/// Is the uplink in the process of buying the selected item?
	var/buying
	///Reference to the currently logged in user's bank account.
	var/datum/bank_account/current_user
	/// List of typepaths for "/datum/market"s that this uplink can access.
	var/list/accessible_markets = list(/datum/market/blackmarket, /datum/market/auction/guns, /datum/market/restock/guns_galore)
	///our current_bid
	var/current_bid = 0

/obj/item/market_uplink/Initialize(mapload)
	. = ..()
	// We don't want to go through this at mapload because the SSblackmarket isn't initialized yet.
	if(mapload)
		return

	update_viewing_category()

/// Simple internal proc for updating the viewing_category variable.
/obj/item/market_uplink/proc/update_viewing_category()
	if(accessible_markets.len)
		viewing_market = accessible_markets[1]
		var/list/categories = SSblackmarket.markets[viewing_market].categories
		if(categories?.len)
			viewing_category = categories[1]

/obj/item/market_uplink/ui_interact(mob/user, datum/tgui/ui)
	if(!viewing_category)
		update_viewing_category()

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BlackMarketUplink", name)
		ui.open()

/obj/item/market_uplink/ui_data(mob/user)
	var/list/data = list()
	var/datum/market/market = viewing_market ? SSblackmarket.markets[viewing_market] : null
	var/obj/item/card/id/id_card
	if(isliving(user))
		var/mob/living/livin = user
		id_card = livin.get_idcard()
	if(id_card?.registered_account)
		current_user = id_card.registered_account
	else
		current_user = null
	data["categories"] = market ? market.categories : null
	data["delivery_methods"] = list()
	if(market)
		for(var/delivery in market.shipping)
			data["delivery_methods"] += list(list("name" = delivery, "price" = market.shipping[delivery]))
	data["money"] = "N/A cr"
	if(current_user)
		data["money"] = current_user.account_balance
	data["buying"] = buying
	data["items"] = list()
	data["viewing_category"] = viewing_category
	data["viewing_market"] = viewing_market
	data["current_bid"] = current_bid
	if(viewing_category && market)
		if(market.market_flags & MARKET_AUCTION)
			var/datum/market/auction/market_auction = market
			data["auction"] = TRUE
			for(var/datum/market_item/auction/item in market_auction.queued_items)
				data["queued_items"] += list(list(
					"time_until_auction" = market_auction.queued_items[item] - world.time,
					"name" = item.name,
					"id" = item.type,
					"starting_cost" = item.price,
				))
			data["bidders"] = list()
			if(market_auction.current_auction)
				data["current_item"] = list(
					"name" = market_auction.current_auction?.name,
					"id" = market_auction.current_auction?.type,
					"desc" = market_auction.current_auction?.desc || market_auction?.current_auction.name,
					"cost" = market_auction.current_auction?.price,
					"top_bidder" = market_auction.current_auction?.top_bidder
				)
				data["bidders"] = market_auction.current_auction?.bidders

			data["time_left"] = COOLDOWN_TIMELEFT(market_auction, current_auction_time)
		else
			if(market.available_items[viewing_category])
				for(var/datum/market_item/I in market.available_items[viewing_category])
					data["auction"] = FALSE
					data["items"] += list(list(
						"id" = I.type,
						"name" = I.name,
						"cost" = I.price,
						"amount" = I.stock,
						"desc" = I.desc || I.name,
					))
	return data

/obj/item/market_uplink/ui_static_data(mob/user)
	var/list/data = list()
	data["delivery_method_description"] = SSblackmarket.shipping_method_descriptions
	data["ltsrbt_built"] = SSblackmarket.telepads.len
	data["markets"] = list()
	for(var/M in accessible_markets)
		var/datum/market/BM = SSblackmarket.markets[M]
		data["markets"] += list(list(
			"id" = M,
			"name" = BM.name
		))
	return data

/obj/item/market_uplink/ui_act(action, params)
	. = ..()
	if(.)
		return
	switch(action)
		if("set_category")
			if(isnull(params["category"]))
				return
			if(isnull(viewing_market))
				return
			if(!(params["category"] in SSblackmarket.markets[viewing_market].categories))
				return
			viewing_category = params["category"]
			. = TRUE
		if("set_market")
			if(isnull(params["market"]))
				return
			var/market = text2path(params["market"])
			if(!(market in accessible_markets))
				return

			viewing_market = market

			var/list/categories = SSblackmarket.markets[viewing_market].categories
			if(categories?.len)
				viewing_category = categories[1]
			else
				viewing_category = null
			. = TRUE
		if("select")
			if(isnull(params["item"]))
				return
			var/item = text2path(params["item"])
			selected_item = item
			buying = TRUE
			. = TRUE
		if("cancel")
			selected_item = null
			buying = FALSE
			. = TRUE
		if("buy")
			if(isnull(params["method"]))
				return
			if(isnull(selected_item))
				buying = FALSE
				return
			var/datum/market/market = SSblackmarket.markets[viewing_market]
			market.pre_purchase(selected_item, viewing_category, params["method"], src, usr, current_bid) // monkestation edit - MODULAR_GUNS

			buying = FALSE
			selected_item = null
		if("set_bid")
			if(isnull(params["bid"]))
				return
			current_bid = params["bid"]
		if("bid")
			var/datum/market/auction/market = SSblackmarket.markets[viewing_market]
			if(!istype(market))
				return
			if(!market.current_auction)
				return
			selected_item = market.current_auction.type
			if(isnull(selected_item))
				return
			market.pre_purchase(selected_item, viewing_category, params["method"], src, usr, current_bid)
		if("reroll")
			var/datum/market/auction/market = SSblackmarket.markets[viewing_market]
			if(!istype(market))
				return
			market.reroll(src, usr)

/obj/item/market_uplink/blackmarket
	name = "\improper Black Market Uplink"
	desc = "An illegal black market uplink. If command wanted you to have these, they wouldn't have made it so hard to get one."
	icon = 'icons/obj/blackmarket.dmi'
	icon_state = "uplink"
	//The original black market uplink
	accessible_markets = list(/datum/market/blackmarket, /datum/market/auction/guns, /datum/market/restock/guns_galore)


/datum/crafting_recipe/blackmarket_uplink
	name = "Black Market Uplink"
	result = /obj/item/market_uplink/blackmarket
	time = 30
	tool_behaviors = list(TOOL_SCREWDRIVER, TOOL_WIRECUTTER, TOOL_MULTITOOL)
	reqs = list(
		/obj/item/stock_parts/micro_laser = 1,
		/obj/item/assembly/signaler = 1,
		/obj/item/stack/cable_coil = 15,
		/obj/item/radio = 1,
		/obj/item/analyzer = 1
	)
	category = CAT_EQUIPMENT

/datum/crafting_recipe/blackmarket_uplink/New()
	..()
	blacklist |= typesof(/obj/item/radio/headset) // because we got shit like /obj/item/radio/off ... WHY!?!
	blacklist |= typesof(/obj/item/radio/intercom)
