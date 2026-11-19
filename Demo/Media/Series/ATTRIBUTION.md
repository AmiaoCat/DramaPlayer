# Drama collection media credits

The 12 short episodes and their posters are adaptations of original Blender Foundation open films. DramaPlayer groups them into three stories and assigns episode titles for the demo. The source footage has been shortened, reframed to 9:16 and re-encoded. Posters are frames from the edited excerpts. The four Tears of Steel excerpts are silent. The Coffee Run and Charge excerpts use the corresponding film audio with short fades.

| Demo assets | Original film and creator | License |
| --- | --- | --- |
| `steel-01`–`steel-04` | [Tears of Steel](https://commons.wikimedia.org/wiki/File:Tears_of_Steel_in_4k_-_Official_Blender_Foundation_release.webm), © Blender Foundation · [Project Mango](https://mango.blender.org/) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `coffee-01`–`coffee-04` | [Coffee Run](https://commons.wikimedia.org/wiki/File:Coffee_Run_-_Blender_Open_Movie-full_movie.webm), © Blender Foundation | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `charge-01`–`charge-04`, `charge-landscape` | [Charge](https://commons.wikimedia.org/wiki/File:Charge_-_Blender_Open_Movie-full_movie.webm), © Blender Foundation / Blender Studio | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

`charge-landscape` includes the same scene as the second vertical Charge excerpt and preserves the film's native widescreen framing and audio.

The edited media remains under the respective Creative Commons licenses above. The repository's MIT license applies to the SDK and demo code. Film names identify the original works and do not indicate endorsement.

Remote playback links to [Tears of Steel on Mux](https://test-streams.mux.dev/) and the [Sintel trailer on W3C](https://www.w3.org/2010/05/video/mediaevents). Both films are by Blender Foundation. See the [Sintel project credits and license](https://durian.blender.org/sharing/).

## Reproduce the media

Save the corresponding Wikimedia 720p transcodes as `steel.webm`, `coffee.webm`, and `charge.webm` in a local source directory. The source pages above link to the available reproductions.

- [Tears of Steel, VP9 720p](https://upload.wikimedia.org/wikipedia/commons/transcoded/1/10/Tears_of_Steel_in_4k_-_Official_Blender_Foundation_release.webm/Tears_of_Steel_in_4k_-_Official_Blender_Foundation_release.webm.720p.vp9.webm)
- [Coffee Run, VP9 720p](https://upload.wikimedia.org/wikipedia/commons/transcoded/3/3f/Coffee_Run_-_Blender_Open_Movie-full_movie.webm/Coffee_Run_-_Blender_Open_Movie-full_movie.webm.720p.vp9.webm)
- [Charge, VP9 720p](https://upload.wikimedia.org/wikipedia/commons/transcoded/7/7a/Charge_-_Blender_Open_Movie-full_movie.webm/Charge_-_Blender_Open_Movie-full_movie.webm.720p.vp9.webm)

The [media preparation script](../../Tools/PrepareSeriesMedia.py) records the clip offsets and crop positions. Run it with Python 3 and an FFmpeg build with VP9/Opus decoding and H.264/AAC encoding.

```sh
python3 Demo/Tools/PrepareSeriesMedia.py /path/to/source-films
```
