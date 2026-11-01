# Scoped extraction. Inputs are scalars from the lone unsharded baseline request.
token_capacity = capacity
max_new_tokens = token_capacity - paged_input - page_size - 1
if requested < max_new_tokens:
    max_new_tokens = requested
if max_new_tokens < 0:
    max_new_tokens = 0
min_free_tokens = capacity - (paged_input + page_size) - max_new_tokens
blocked = min_free_tokens <= reserve
