class_name InvoPlayerCopy
extends RefCounted
## Player-facing copy for API failures, word for word the Unity kit's
## (SenderCurrencyPanel, TransferCurrencyPanel, ItemPurchaseConfirmPanel).
## Never shows the raw response: an error body can carry another player's
## phone number or email.


static func is_network_error(e: InvoError) -> bool:
	return e.status == 0 and e.code.is_empty()


static func is_rate_limited(e: InvoError) -> bool:
	return e.status == 429 or e.code == "rate_limited"


static func _seconds(e: InvoError, fallback: int) -> int:
	var s: float = e.retry_after_seconds()
	return int(ceil(s)) if s >= 0.0 else fallback


static func _plural(n: int) -> String:
	return "%d second%s" % [n, "" if n == 1 else "s"]


static func send(e: InvoError) -> String:
	if e == null:
		return "Something went wrong. Please try again."
	if is_network_error(e):
		return "No connection. Check your network and try again."
	if is_rate_limited(e):
		return "Too many attempts. Try again in %s." % _plural(_seconds(e, 60))
	if e.is_phone_share_approval_required():
		return "This phone number is shared with another account, so it needs approval before " + \
				"currency can move. The account holder must approve the number in the Invo app, then try again."
	if e.is_duplicate_request():
		return "That request was already processed. Nothing was charged twice."
	if e.code == "TENANT_NOT_MIGRATED":
		return "Phone approval is not enabled for this game yet. Contact Invo to enable it."
	match e.status:
		400:
			return "Some details were not accepted. Check the phone numbers and amount."
		401, 403:
			return "This game is not allowed to complete that request."
		404:
			return "We could not find that send. It may have expired or been claimed already."
		410:
			return "That approval is no longer valid. Start the send again."
		503:
			return "Invo is briefly unavailable. Please try again in a moment."
	if e.status >= 500:
		return "Invo had a problem completing that. Please try again." + _ref(e, "Ref")
	return "That request could not be completed. Please try again."


static func transfer(e: InvoError, fallback: String = "That transfer could not be completed. Please try again.") -> String:
	if e == null:
		return fallback
	var message: String = fallback
	if is_network_error(e):
		message = "No connection to Invo. Check your internet and try again."
	elif is_rate_limited(e):
		message = "Too many attempts. Try again in %s." % _plural(_seconds(e, 30))
	elif e.code == "GUARDIAN_REQUIRED":
		message = "This account needs a parent or guardian linked in the Invo app before it can transfer currency."
	elif e.is_phone_share_approval_required():
		message = "That number is shared with another Invo account and has to be approved with a one-time code first."
	elif e.code == "TENANT_NOT_MIGRATED":
		message = "Phone approval is not enabled for this game yet. Contact Invo to enable it."
	elif e.status == 403:
		message = "Invo declined this transfer for this account."
	elif e.is_duplicate_request():
		message = "This transfer was already submitted. Check your balance before trying again."
	elif e.status >= 500:
		message = "Invo is having trouble right now. Try again in a few minutes."
	return message + _ref(e, "ref")


static func purchase(e: InvoError) -> String:
	if is_network_error(e):
		return "No connection. Check your network and try again."
	if is_rate_limited(e):
		return "Too many attempts. Please wait before trying again."
	if e.is_duplicate_request():
		return "This purchase already went through."
	if e.status == 401 or e.status == 403:
		return "This game is not authorised to complete the purchase."
	if e.status >= 500:
		return "The store is having trouble. Please try again shortly."
	if e.is_insufficient_balance():
		return "You do not have enough balance for this item."
	return "That purchase could not be completed."


static func store(e: InvoError) -> String:
	if is_network_error(e):
		return "No connection. Check your network and try again."
	return "The store could not be loaded. Please try again."


static func _ref(e: InvoError, word: String) -> String:
	return "" if e.request_id.is_empty() else " (%s %s)" % [word, e.request_id]
