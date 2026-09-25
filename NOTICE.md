# Third-party notices

Tinycast is licensed under the GNU Affero General Public License v3 — see [LICENSE](LICENSE). It
also redistributes the third-party material recorded below, under the terms stated for each.

## Brand marks — `Tinycast/Assets.xcassets/AIBrand*.imageset`

Thirteen monochrome template SVGs, ~300 B–2 KB each, drawn beside a model's name in the model
picker and the chat header so a route is recognisable at a glance.

Every mark is the trademark of the company it identifies. Tinycast uses them only to name that
company's own models inside its own UI. No affiliation, sponsorship or endorsement is implied, and
none of these companies has reviewed or approved Tinycast.

### Simple Icons — twelve marks

`claude`, `deepseek`, `googlegemini`, `kimi`, `meta`, `minimax`, `mistralai`, `openai`,
`openrouter`, `perplexity`, `qwen` and `x`, from <https://github.com/simple-icons/simple-icons>.

The Simple Icons **project** is released under CC0 1.0 Universal. Its own disclaimer is explicit
that this does not extend to every mark the project carries: the icons depict third-party brands
whose trademarks stay with their owners, and the absence of licence data for a given icon does not
imply the icon is unlicensed. Anyone redistributing Tinycast, or reusing these files from it,
should read the disclaimer and satisfy themselves about the brands involved:
<https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md>.

### Lobe Icons — one mark

`zai`, from <https://github.com/lobehub/lobe-icons>, which is MIT licensed. Its licence requires
this notice to travel with the work:

```
MIT License

Copyright (c) 2023 LobeHub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Rooms — window rooms, their layouts and the gliding layout preview

Window Management's rooms adapt code from **Rooms** by Sara Gordić,
<https://github.com/saragordic/rooms>, used with the author's permission and under its MIT
licence. The room model, the layout and grid engines, arrangement reading, window matching,
parking and its ledger, the pass that walks into a room, and the animated layout preview all
follow that project. Every adapted file says so on its first line, with a link to the licence:

- `Tinycast/Features/WindowManagement/Model/`: `Room.swift`, `RoomWindow.swift`,
  `RoomLayoutKind.swift`, `RoomLayoutEngine.swift`, `RoomGrid.swift`, `RoomArrangement.swift`,
  `RoomWindowMatcher.swift`, `RoomParking.swift`, `RoomParkingLedger.swift`, `RoomPlan.swift` and
  `RoomMinimumSizeStore.swift`
- `Tinycast/Features/WindowManagement/Service/`: `RoomRunner.swift`, `RoomWindowSweep.swift`, and
  the window-number lookup in `AXWindowAccess.swift`
- `Tinycast/Features/WindowManagement/UI/`: `RoomCoordinator.swift`, `RoomsScreen.swift`,
  `RoomPickerScreen.swift`, `RoomPreviewController.swift` and `RoomPreviewView.swift`
- `Tests/window-room-test.swift`, whose cases follow Rooms' own tests

Its licence requires this notice to travel with the work:

```
MIT License

Copyright (c) 2026 Sara Gordić

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
