#include "Parallel.h"

#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/callable_custom.hpp>

#include <algorithm>

namespace {

class RangeCallable : public godot::CallableCustom {
public:
    RangeCallable(size_t begin, size_t end, size_t batch, const std::function<void(size_t)>& function)
        : m_begin(begin)
        , m_end(end)
        , m_batch(batch)
        , m_function(function) {}

    uint32_t hash() const override {
        return static_cast<uint32_t>(reinterpret_cast<uintptr_t>(this));
    }

    godot::String get_as_text() const override {
        return "parallel_for";
    }

    CompareEqualFunc get_compare_equal_func() const override {
        return [](const godot::CallableCustom* a, const godot::CallableCustom* b) { return a == b; };
    }

    CompareLessFunc get_compare_less_func() const override {
        return [](const godot::CallableCustom* a, const godot::CallableCustom* b) { return a < b; };
    }

    bool is_valid() const override {
        return true;
    }

    godot::ObjectID get_object() const override {
        return godot::ObjectID();
    }

    void call(const godot::Variant** args, int argcount, godot::Variant& r_return, GDExtensionCallError& r_error) const override {
        int64_t index = argcount > 0 ? static_cast<int64_t>(*args[0]) : 0;

        size_t start = m_begin + static_cast<size_t>(index) * m_batch;
        size_t stop = std::min(m_end, start + m_batch);

        for (size_t i = start; i < stop; i++) {
            m_function(i);
        }

        r_error.error = GDEXTENSION_CALL_OK;
    }

private:
    size_t m_begin;
    size_t m_end;
    size_t m_batch;
    const std::function<void(size_t)>& m_function;
};

}

void parallel_for(size_t begin_index, size_t end_index, const std::function<void(size_t)>& function) {
    if (begin_index >= end_index) {
        return;
    }

    godot::WorkerThreadPool* pool = godot::WorkerThreadPool::get_singleton();
    size_t size = end_index - begin_index;

    if (!pool || size == 1) {
        for (size_t i = begin_index; i < end_index; i++) {
            function(i);
        }

        return;
    }

    size_t workers = godot::OS::get_singleton() ? static_cast<size_t>(godot::OS::get_singleton()->get_processor_count()) : 4;
    size_t batches = std::min(size, std::max<size_t>(1, workers * 2));
    size_t batch_size = (size + batches - 1) / batches;

    godot::Callable callable(memnew(RangeCallable(begin_index, end_index, batch_size, function)));

    int64_t group = pool->add_group_task(callable, static_cast<int64_t>(batches), -1, false, "regolith");
    pool->wait_for_group_task_completion(group);
}
