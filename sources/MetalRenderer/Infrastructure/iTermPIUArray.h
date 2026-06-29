//
//  iTermPIUArray.h
//  iTerm2
//
//  Created by George Nachman on 12/19/17.
//

#import <vector>

namespace iTerm2 {
    // A PIUArray is an array of arrays of PIU structs. This avoids giant allocations.
    // It is append-only.
    template<class T>
    class PIUArray {
    public:
        // Maximum number of PIUs in one segment.
        const static size_t DEFAULT_CAPACITY = 1024;

        PIUArray() : _capacity(DEFAULT_CAPACITY), _size(0) {
            _arrays.resize(1);
            _arrays.back().reserve(_capacity);
        }

        explicit PIUArray(size_t capacity) : _capacity(capacity), _size(0) {
            _arrays.resize(1);
            _arrays.back().reserve(_capacity);
        }

        // Move constructor - O(1) transfer of ownership
        PIUArray(PIUArray&& other) noexcept
            : _capacity(other._capacity), _size(other._size), _arrays(std::move(other._arrays)) {
            other._size = 0;
        }

        // Move assignment - O(1) transfer of ownership
        PIUArray& operator=(PIUArray&& other) noexcept {
            if (this != &other) {
                _capacity = other._capacity;
                _size = other._size;
                _arrays = std::move(other._arrays);
                other._size = 0;
            }
            return *this;
        }

        // Delete copy operations to prevent accidental copies
        PIUArray(const PIUArray&) = delete;
        PIUArray& operator=(const PIUArray&) = delete;

        T *get_next() {
            if (_arrays.back().size() == _capacity) {
                _arrays.resize(_arrays.size() + 1);
                _arrays.back().reserve(_capacity);
            }

            std::vector<T> &array = _arrays.back();
            array.resize(array.size() + 1);
            _size++;
            return &array.back();
        }

        T &get(const size_t &segment, const size_t &index) {
            return _arrays[segment][index];
        }

        T &get(const size_t &index) {
            return _arrays[index / _capacity][index % _capacity];
        }

        void push_back(const T &piu) {
            memmove(get_next(), &piu, sizeof(piu));
        }

        size_t get_number_of_segments() const {
            return _arrays.size();
        }

        const T *start_of_segment(const size_t segment) const {
            return &_arrays[segment][0];
        }

        size_t size_of_segment(const size_t segment) const {
            return _arrays[segment].size();
        }

        const size_t &size() const {
            return _size;
        }

    private:
        size_t _capacity;
        size_t _size;
        std::vector<std::vector<T>> _arrays;
    };
}
