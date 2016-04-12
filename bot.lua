HTTP = require('socket.http')
HTTPS = require('ssl.https')
URL = require('socket.url')
JSON = require('dkjson')
redis = require('redis')
client = Redis.connect('127.0.0.1', 6379)
--serpent = require('serpent')

version = '3.1'

bot_init = function(on_reload) -- The function run when the bot is started or reloaded.

	config = dofile('config.lua') -- Load configuration file.
	dofile('bindings.lua') -- Load Telegram bindings.
	dofile('utilities.lua') -- Load miscellaneous and cross-plugin functions.
	lang = dofile('languages.lua') -- All the languages available
	
	bot = nil
	while not bot do -- Get bot info and retry if unable to connect.
		bot = getMe()
	end
	bot = bot.result

	plugins = {} -- Load plugins.
	for i,v in ipairs(config.plugins) do
		local p = dofile('plugins/'..v)
		table.insert(plugins, p)
	end
	
	preprocess = dofile('preprocess.lua')

	print('BOT RUNNING: @'..bot.username .. ', AKA ' .. bot.first_name ..' ('..bot.id..')')
	if not on_reload then
		sendMessage(config.admin, '*Bot started!*\n_'..os.date('On %A, %d %B %Y\nAt %X')..'_', true, false, true)
	end
	
	-- Generate a random seed and "pop" the first random number. :)
	math.randomseed(os.time())
	math.random()

	last_update = last_update or 0 -- Set loop variables: Update offset,
	last_cron = last_cron or os.time() -- the time of the last cron job,
	is_started = true -- whether the bot should be running or not.

end

local function get_from(msg)
	local user = msg.from.first_name
	if msg.from.last_name then
		user = user..' '..msg.from.last_name
	end
	if msg.from.username then
		user = user..' [@'..msg.from.username..']'
	end
	user = user..' ('..msg.from.id..')'
	return user
end

local function get_what(msg)
	if msg.sticker then
		return 'sticker'
	elseif msg.photo then
		return 'photo'
	elseif msg.document then
		return 'document'
	elseif msg.audio then
		return 'audio'
	elseif msg.video then
		return 'video'
	elseif msg.voice then
		return 'voice'
	elseif msg.contact then
		return 'contact'
	elseif msg.location then
		return 'location'
	elseif msg.text then
		return 'text'
	else
		return 'service message'
	end
end

on_msg_receive = function(msg) -- The fn run whenever a message is received.
	print('\nNEW MESSAGE\nFrom: '..get_from(msg)..'\nType: '..msg.chat.type..'\nWhat: '..get_what(msg)..'\nWhen: '..os.date('On %A, %d %B %YAt %X'))
	
	if msg.date < os.time() - 5 then return end -- Do not process old messages.
	if not msg.text then msg.text = msg.caption or '' end

	if msg.text:match('^/start .+') then
		msg.text = '/' .. msg.text:input()
	end
	
	--Group language
	local group_lang = client:get('lang:'..msg.chat.id)
	if not group_lang then
		group_lang = 'en'
	end
	
	--count the number of messages
	client:hincrby('bot:general', 'messages', 1)
	
	--preprocess each message
	preprocess(msg, group_lang)
	
	for i,v in pairs(plugins) do
		--vardump(v)
		for k,w in pairs(v.triggers) do
			local blocks = match_pattern(w, msg.text)
			if blocks then
				if blocks[1] ~= '' then
      				print("Match found: ", w)
      			end
				
				msg.text_lower = msg.text:lower()
				
				local success, result = pcall(function()
					return v.action(msg, blocks, group_lang)
				end)
				if not success then
					sendReply(msg, 'Something went wrong.\nPlease report the problem with "/c <bug>"', true)
					print(msg.text, result)
          			sendMessage( tostring(config.admin), result..'\n'..msg.from.id..'\n'..msg.text, false, false, false)
					return
				end
				-- If the action returns a table, make that table msg.
				if type(result) == 'table' then
					msg = result
				-- If the action returns true, don't stop.
				elseif result ~= true then
					return
				end
			end
		end
	end

end



local function service_to_message(msg)
	local service
	local event
	if msg.new_chat_member then
		if tonumber(msg.new_chat_member.id) == tonumber(bot.id) then
			event = '###botadded'
		else
			event = '###added'
		end
		service = {
			chat = msg.chat,
    		date = msg.date,
    		adder = msg.from,
    		from = msg.from,
    		message_id = message_id,
    		added = msg.new_chat_member,
    		text = event
    	}
	else
		if tonumber(msg.left_chat_member.id) == tonumber(bot.id) then
			event = '###botremoved'
		else
			event = '###removed'
		end
		service = {
			chat = msg.chat,
    		date = msg.date,
    		remover = msg.from,
    		from = msg.from,
    		message_id = message_id,
    		removed = msg.left_chat_member,
    		text = event
    	}
	end
	
    return on_msg_receive(service)
end

local function forward_to_msg(msg)
	if msg.text then
		msg.text = '###forward:'..msg.text
	else
		msg.text = '###forward'
	end
    return on_msg_receive(msg)
end

local function inline_to_msg(inline)
	local msg = {
		id = inline.id,
    	chat = {
      		id = inline.id,
      		type = 'inline',
      		title = inline.from.first_name
    	},
    	from = inline.from,
		message_id = math.random(1,800),
    	text = '###inline:'..inline.query,
    	query = inline.query,
    	date = os.time() + 100
    }
    --vardump(msg)
    client:hincrby('bot:general', 'inline', 1)
    return on_msg_receive(msg)
end

local function media_to_msg(msg)
	if msg.photo then
		msg.text = '###image'
	elseif msg.video then
		msg.text = '###video'
	elseif msg.audio then
		msg.text = '###audio'
	elseif msg.voice then
		msg.text = '###voice'
	elseif msg.document then
		msg.text = '###file'
	elseif msg.sticker then
		msg.text = '###sticker'
	elseif msg.contact then
		msg.text = '###contact'
	end
	msg.media = true
	return on_msg_receive(msg)
end


---------WHEN THE BOT IS STARTED FROM THE TERMINAL, THIS IS THE FIRST FUNCTION HE FOUNDS

bot_init() -- Actually start the script. Run the bot_init function.

while is_started do -- Start a loop while the bot should be running.

	local res = getUpdates(last_update+1) -- Get the latest updates!
	if res then
		--vardump(res)
		--print('\n\n\n')
		for i,msg in ipairs(res.result) do -- Go through every new message.
			last_update = msg.update_id
			--vardump(v)
			
			if msg.message then
				if msg.message.new_chat_member or msg.message.left_chat_member then
					print('service triggered')
					service_to_message(msg.message)
				elseif msg.message.photo or msg.message.video or msg.message.document or msg.message.voice or msg.message.audio or msg.message.sticker then
					print('media triggered')
					media_to_msg(msg.message)
				elseif msg.message.forward_from then
					print('forward triggered')
					forward_to_msg(msg.message)
				else
					on_msg_receive(msg.message)
				end
			end
		end
	else
		print(config.errors.connection)
	end

	if last_cron < os.time() - 5 then -- Run cron jobs if the time has come.
		for i,v in ipairs(plugins) do
			if v.cron then -- Call each plugin's cron function, if it has one.
				local res, err = pcall(function() v.cron() end)
				if not res then print('ERROR: '..err) end
			end
		end
		last_cron = os.time() -- And finally, update the variable.
	end

end

print('Halted.')