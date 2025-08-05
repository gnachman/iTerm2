// Match structure with segment-based coordinates
class Match {
    constructor(coordinates, text) {
        this.id = Math.random().toString(36).substr(2, 9); // Generate unique ID
        this.coordinates = coordinates;  // Array representing position [segment1, segment2, ..., localPos]
        this.text = text;                // The matched text
        this.type = null;                // 'local' or 'remote'
        this.highlightElements = [];     // For local matches
        this.revealers = new Set();      // For local matches

        // For remote matches
        this.frameId = null;
        this.remoteIndex = null;
        this.contextBefore = null;
        this.contextAfter = null;
    }

    // Compare two matches for ordering
    static compare(a, b) {
        // Lexicographic comparison of coordinate arrays
        const minLen = Math.min(a.coordinates.length, b.coordinates.length);
        for (let i = 0; i < minLen; i++) {
            if (a.coordinates[i] < b.coordinates[i]) return -1;
            if (a.coordinates[i] > b.coordinates[i]) return 1;
        }
        // If all compared elements are equal, shorter array comes first
        return a.coordinates.length - b.coordinates.length;
    }
}
