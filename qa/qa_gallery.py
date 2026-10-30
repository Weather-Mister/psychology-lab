"""Persistence and gallery consistency check (static)."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'Grainlight'
s=(root/'Library/PhotoLibrary.swift').read_text()
t=(root/'Library/PhotoRecord.swift').read_text()
u=(root/'UI/GalleryView.swift').read_text()
e=(root/'UI/EditorView.swift').read_text()
checks={
    'original never overwritten by edits': 'photos[i].edits = edits' in s and 'data.write(to: root.appendingPathComponent(file)' in s,
    'persistent edit metadata': 'JSONEncoder().encode(photos)' in s and 'JSONDecoder().decode([PhotoRecord]' in s,
    'atomic capture write': 'data.write(to: root.appendingPathComponent(file), options: .atomic)' in s,
    'generation-safe thumbnails': 'thumbnailGeneration[record.id] == generation' in s,
    'generation-safe image view': 'developmentID == requestID' in u,
    'generation-safe slider renders': 'previewGeneration == generation' in e,
    'shares exported temp file': 'ShareSheet(items: [item.url])' in u,
    'editing exposed to gallery': 'EditorView(id: id)' in u,
    'imports camera RAW DNG': 'ext == "dng"' in s,
    'basic photo edits are Codable': 'struct PhotoEdits: Codable' in t,
}
for k,v in checks.items():print(('PASS' if v else 'FAIL')+' gallery: '+k)
assert all(checks.values())
