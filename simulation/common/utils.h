#ifndef _PROCYON_UTILS_
#define _PROCYON_UTILS_

namespace procyon {
    namespace utils {
        void load_hex(const std::string& filename, std::vector<uint8_t>& m_vec);
        void load_hex(const std::string& filename, uint8_t *m_buf, size_t size);
        void load_bin(const std::string& filename, std::vector<uint8_t>& m_vec);
        void load_bin(const std::string& filename, uint8_t *m_buf, size_t size);

        void dump_mem(const std::vector<uint8_t>& m_vec);
        void dump_mem(uint8_t *m_buf, size_t size);
    }
}

#endif // _PROCYON_UTILS_
