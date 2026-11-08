extends RefCounted

# Activity previews share an atomic stock and receipt update. The caller owns
# its stock limits, ticket namespace and the stage transition after acceptance.
static func exchange(account: Dictionary, ticket: String, changes: Dictionary, credits: int,
		details: Dictionary, capacity: Callable, stock_check: Callable, receipt_limit: int) -> Dictionary:
	var prior: Dictionary = account["receipts"].get(ticket, {})
	if not prior.is_empty():
		return {"ok": true, "account": account, "receipt": prior.duplicate(true), "replayed": true}
	var stock: Dictionary = account["stock"].duplicate()
	for key in changes:
		var next: int = int(stock.get(key, 0)) + int(changes[key])
		var limit: int = capacity.call(key)
		if limit <= 0 or next < 0: return {"ok":false,"reason":"missing"}
		if next > limit: return {"ok":false,"reason":"capacity"}
		stock[key] = next
	var reason: String = stock_check.call(stock) if stock_check.is_valid() else ""
	if not reason.is_empty(): return {"ok":false,"reason":reason}
	var paid: int = 0 if int(account["cash"]) < 0 else credits
	var balance: int = int(account["cash"]) + paid
	if account["cash"] >= 0 and balance < 0: return {"ok":false,"reason":"balance"}
	var receipt: Dictionary = {"ok":true,"id":ticket,"stock":changes.duplicate(),"credits":paid}
	receipt.merge(details)
	var receipts: Dictionary = account["receipts"].duplicate()
	receipts[ticket] = receipt
	if receipts.size() > receipt_limit: receipts.erase(receipts.keys()[0])
	return {"ok":true,"account":{"stock":stock,"cash":balance,"receipts":receipts},
		"receipt":receipt.duplicate(true),"replayed":false}
