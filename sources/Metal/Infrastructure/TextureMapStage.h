//
//  TextureMapStage.h
//  iTerm2
//
//  Created by George Nachman on 11/19/17.
//

#include <unordered_set>
#include <vector>

namespace iTerm2 {
struct TextureEntry {
    int index;
    BOOL emoji;
};

class TextureMapStage {
private:
    // Maps stage indexes that need blitting to their destination indices.
    std::unordered_map<int, int> _indexesToBlit;

    // Held locks
    std::vector<int> _lockedIndexes;

    int _nextStageIndex;
public:
    // Prepare for the next frame
    void reset() {
        _indexesToBlit.clear();
        _lockedIndexes.clear();
        _nextStageIndex = 0;
    }

    int will_blit(const int index) {
        const int stageIndex = _nextStageIndex++;
        _indexesToBlit[stageIndex] = index;
        return stageIndex;
    }

    const bool have_indexes_to_blit() const {
        return !_indexesToBlit.empty();
    }

    void blit(iTermTextureArray *source, iTermTextureArray *destination, id <MTLBlitCommandEncoder> blitter) {
        for (auto it = _indexesToBlit.begin(); it != _indexesToBlit.end(); it++) {
            [source copyTextureAtIndex:it->first
                               toArray:destination
                                 index:it->second
                               blitter:blitter];
        }
        _indexesToBlit.clear();
        _nextStageIndex = 0;
    }

    void unlock_all() {
        _lockedIndexes.clear();
    }

};
}
