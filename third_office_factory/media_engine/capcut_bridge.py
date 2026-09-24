"""Third Office - CapCut Studio Bridge Adapter.

Integrates CapCut Web Magic Tools into PHANTOM GRID Third Office:
1. Generates structured storyboard scripts for AI Script-to-Video.
2. Exports synchronized SRT subtitle files.
3. Generates direct deep-links to Commander's personal CapCut workspace.
4. Prepares ammo assets (Video clips, Voiceover audio, Subtitles) for one-click drag & drop.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field


@dataclass
class StoryboardScene:
    scene_index: int
    duration_seconds: float
    narration_text: str
    visual_prompt: str
    screen_asset: str = ""


@dataclass
class CapCutProjectPackage:
    project_id: str
    project_title: str
    workspace_url: str
    scenes: list[StoryboardScene] = field(default_factory=list)
    output_dir: str = "third_office_factory/out_delivery/capcut_assets"

    def to_full_script(self) -> str:
        return " ".join(s.narration_text for s in self.scenes)

    def generate_srt(self) -> str:
        srt_lines = []
        current_time = 0.0
        for s in self.scenes:
            start_h = int(current_time // 3600)
            start_m = int((current_time % 3600) // 60)
            start_s = int(current_time % 60)
            start_ms = int((current_time - int(current_time)) * 1000)

            end_time = current_time + s.duration_seconds
            end_h = int(end_time // 3600)
            end_m = int((end_time % 3600) // 60)
            end_s = int(end_time % 60)
            end_ms = int((end_time - int(end_time)) * 1000)

            srt_lines.append(f"{s.scene_index}")
            srt_lines.append(
                f"{start_h:02d}:{start_m:02d}:{start_s:02d},{start_ms:03d} --> "
                f"{end_h:02d}:{end_m:02d}:{end_s:02d},{end_ms:03d}"
            )
            srt_lines.append(s.narration_text)
            srt_lines.append("")
            current_time = end_time

        return "\n".join(srt_lines)


class CapCutBridgeAdapter:
    """The official Bridge Adapter for CapCut Web Studio in Third Office."""

    COMMANDER_WORKSPACE_URL = (
        "https://www.capcut.com/editor/DEAAE8F4-CCDA-4BC8-8438-0E4C89BFD41B"
        "?enter_from=create_new&from_page=work_space&__action_from=magic_tools"
        "&position=magic_tools&scenario=custom&workspaceId=7688723178012540935"
        "&spaceId=7688722658510734343"
    )

    def __init__(self, out_dir: str = "third_office_factory/out_delivery/capcut_assets") -> None:
        self.out_dir = out_dir
        os.makedirs(self.out_dir, exist_ok=True)

    def build_project_package(
        self,
        project_id: str,
        project_title: str,
        narration_scenes: list[tuple[float, str, str]],
    ) -> CapCutProjectPackage:
        scenes = [
            StoryboardScene(
                scene_index=idx + 1,
                duration_seconds=dur,
                narration_text=text,
                visual_prompt=prompt,
            )
            for idx, (dur, text, prompt) in enumerate(narration_scenes)
        ]

        pkg = CapCutProjectPackage(
            project_id=project_id,
            project_title=project_title,
            workspace_url=self.COMMANDER_WORKSPACE_URL,
            scenes=scenes,
            output_dir=self.out_dir,
        )

        # Export SRT
        srt_path = os.path.join(self.out_dir, f"{project_id}.srt")
        with open(srt_path, "w", encoding="utf-8") as f:
            f.write(pkg.generate_srt())

        # Export Storyboard JSON
        manifest_path = os.path.join(self.out_dir, f"{project_id}_storyboard.json")
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "project_id": pkg.project_id,
                    "title": pkg.project_title,
                    "workspace_url": pkg.workspace_url,
                    "full_script": pkg.to_full_script(),
                    "scenes": [
                        {
                            "index": s.scene_index,
                            "duration": s.duration_seconds,
                            "narration": s.narration_text,
                            "visual_prompt": s.visual_prompt,
                        }
                        for s in pkg.scenes
                    ],
                },
                f,
                indent=2,
                ensure_ascii=False,
            )

        return pkg
