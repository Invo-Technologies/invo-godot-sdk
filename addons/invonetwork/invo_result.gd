class_name InvoResult
extends RefCounted
## Result wrapper for every async SDK call (GDScript has no exceptions).
##
##     var result: InvoResult = await Invo.client().get_balance()
##     if result.ok:
##         print(result.data)
##     else:
##         push_warning(result.error.message)

var ok: bool = false
## Parsed response payload (Dictionary for every INVO endpoint).
var data: Variant = null
## Set when ok == false.
var error: InvoError = null


static func success(p_data: Variant) -> InvoResult:
	var r: InvoResult = InvoResult.new()
	r.ok = true
	r.data = p_data
	return r


static func failure(p_error: InvoError) -> InvoResult:
	var r: InvoResult = InvoResult.new()
	r.ok = false
	r.error = p_error
	return r


## data as a Dictionary ({} for non-dict payloads) — the common case.
func dict() -> Dictionary:
	return data if data is Dictionary else {}
