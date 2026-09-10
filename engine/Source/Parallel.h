#pragma once

#include <cstddef>
#include <functional>

// runs function(i) for i in [begin, end) across godot's WorkerThreadPool and
// blocks until every index finished. safe to nest, the pool yields the
// waiting thread to other tasks
void parallel_for(size_t begin_index, size_t end_index, const std::function<void(size_t)>& function);
