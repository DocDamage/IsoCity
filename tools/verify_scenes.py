"""Run Godot's import and real asset/behavior checks from any working directory."""
from pathlib import Path
import os
import re
import shutil
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def free_port():
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        return str(connection.getsockname()[1])


def main():
    portable_start = None
    if '--from-portable-check' in sys.argv:
        index = sys.argv.index('--from-portable-check') + 1
        if index == len(sys.argv) or '--from-check' in sys.argv:
            print('Use --from-portable-check NAME by itself to resume the standalone checks.', file=sys.stderr)
            return 2
        portable_start = sys.argv[index]
    godot = os.environ.get('GODOT_BIN') or next(
        (path for name in ('godot_console', 'godot', 'godot4')
         if (path := shutil.which(name))), None)
    if not godot:
        print('Godot was not found. Put Godot 4.7+ on PATH or set GODOT_BIN to the executable.', file=sys.stderr)
        return 1
    preview_rules = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_model_previews.py'], cwd=ROOT)
    if preview_rules.returncode: return preview_rules.returncode
    functional_rules = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_functional_defaults.py'], cwd=ROOT)
    if functional_rules.returncode: return functional_rules.returncode
    metadata_rules = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_asset_metadata.py'], cwd=ROOT)
    if metadata_rules.returncode: return metadata_rules.returncode
    reviewed_rules = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_reviewed_sprites.py'], cwd=ROOT)
    if reviewed_rules.returncode: return reviewed_rules.returncode
    name_rules = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_reviewed_names.py'], cwd=ROOT)
    if name_rules.returncode: return name_rules.returncode
    theme_rules = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_asset_themes.py'], cwd=ROOT)
    if theme_rules.returncode: return theme_rules.returncode
    render_variants = subprocess.run([sys.executable, str(ROOT / 'tools' / 'prepare_render_variants.py'), '--check'], cwd=ROOT)
    if render_variants.returncode: return render_variants.returncode
    semantic_rules = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_asset_semantics.py'], cwd=ROOT)
    if semantic_rules.returncode: return semantic_rules.returncode
    companion_rules = subprocess.run([sys.executable, str(ROOT / 'tools' / 'compile_asset_companions.py'), '--check'], cwd=ROOT)
    if companion_rules.returncode: return companion_rules.returncode
    zoning_rules = subprocess.run([sys.executable, str(ROOT / 'tools' / 'compile_zoning_candidates.py'), '--check'], cwd=ROOT)
    if zoning_rules.returncode: return zoning_rules.returncode
    neighborhood_rules = subprocess.run([sys.executable, str(ROOT / 'tools' / 'compile_neighborhood_palettes.py'), '--check'], cwd=ROOT)
    if neighborhood_rules.returncode: return neighborhood_rules.returncode
    if os.name == 'nt':
        collection_writes = subprocess.run([sys.executable, str(ROOT / 'tools' / 'verify_asset_collection_writes.py')], cwd=ROOT)
        if collection_writes.returncode: return collection_writes.returncode
    checks = [
        # Separate ports let verification run while the interactive editor is open.
        ('import', ['--import', '--lsp-port', free_port(), '--dap-port', free_port()]),
        ('assets', ['--script', 'res://tools/test_all_assets.gd']),
        ('model_previews', ['--script', 'res://tools/test_model_previews.gd', '--', '--test']),
        ('functional_defaults', ['--fixed-fps', '60', '--script', 'res://tools/test_functional_defaults.gd', '--', '--test']),
        ('asset_families', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_families.gd', '--', '--test']),
        ('reviewed_sprites', ['--fixed-fps', '60', '--script', 'res://tools/test_reviewed_sprites.gd', '--', '--test', '--consumer-ui']),
        ('reviewed_names', ['--fixed-fps', '60', '--script', 'res://tools/test_reviewed_names.gd', '--', '--test', '--consumer-ui']),
        ('asset_themes', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_themes.gd', '--', '--test', '--consumer-ui']),
        ('asset_capabilities', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_capabilities.gd', '--', '--test', '--consumer-ui']),
        ('asset_scale_preview', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_scale_preview.gd', '--', '--test', '--consumer-ui']),
        ('style_suggestions', ['--fixed-fps', '60', '--script', 'res://tools/test_style_suggestions.gd', '--', '--test', '--consumer-ui']),
        ('semantic_search', ['--fixed-fps', '60', '--script', 'res://tools/test_semantic_search.gd', '--', '--test', '--consumer-ui']),
        ('asset_health', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_health.gd', '--', '--test']),
        ('asset_health_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_health_workflow.gd', '--', '--test', '--consumer-ui']),
        ('interaction_anchors', ['--fixed-fps', '60', '--script', 'res://tools/test_interaction_anchors.gd', '--', '--test', '--consumer-ui']),
        ('interior_kits', ['--fixed-fps', '60', '--script', 'res://tools/test_interior_kits.gd', '--', '--test']),
        ('interior_kits_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_interior_kits_workflow.gd', '--', '--test', '--consumer-ui']),
        ('owned_room_copy', ['--fixed-fps', '60', '--script', 'res://tools/test_owned_room_copy_workflow.gd', '--', '--test', '--consumer-ui']),
        ('task_collections', ['--fixed-fps', '60', '--script', 'res://tools/test_task_collections.gd', '--', '--test', '--consumer-ui']),
        ('interior_kit_plan', ['--fixed-fps', '60', '--script', 'res://tools/test_interior_kit_plan.gd', '--', '--test']),
        ('interior_shells_current', ['--script', 'res://tools/prepare_interior_shells.gd', '--', '--check']),
        ('interior_kit_preview', ['--fixed-fps', '60', '--script', 'res://tools/test_interior_kit_preview.gd', '--', '--test']),
        ('interior_kit_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_interior_kit_workflow.gd', '--', '--test', '--consumer-ui']),
        ('interior_kit_delivery', ['--fixed-fps', '60', '--script', 'res://tools/test_interior_kit_delivery.gd', '--', '--test', '--consumer-ui']),
        ('interior_kit_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_interior_kit_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('asset_recents', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_recents.gd', '--', '--test']),
        ('recent_asset_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_recent_asset_workflow.gd', '--', '--test', '--consumer-ui']),
        ('recent_asset_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_recent_asset_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('companion_plan', ['--fixed-fps', '60', '--script', 'res://tools/test_companion_plan.gd', '--', '--test']),
        ('companion_preview', ['--fixed-fps', '60', '--script', 'res://tools/test_companion_preview.gd', '--', '--test']),
        ('companion_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_companion_workflow.gd', '--', '--test', '--consumer-ui']),
        ('companion_delivery', ['--fixed-fps', '60', '--script', 'res://tools/test_companion_delivery.gd', '--', '--test', '--consumer-ui']),
        ('companion_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_companion_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('companion_accessibility', ['--fixed-fps', '60', '--script', 'res://tools/test_companion_accessibility.gd', '--', '--test', '--consumer-ui']),
        ('asset_collections', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_collections.gd', '--', '--test']),
        ('asset_collection_index', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_collection_index.gd', '--', '--test']),
        ('project_palette_document', ['--fixed-fps', '60', '--script', 'res://tools/test_project_palette_document.gd', '--', '--test']),
        ('project_palette_policy', ['--fixed-fps', '60', '--script', 'res://tools/test_project_palette_policy.gd', '--', '--test']),
        ('collection_recovery', ['--fixed-fps', '60', '--script', 'res://tools/test_collection_recovery.gd', '--', '--test']),
        ('collection_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_collection_workflow.gd', '--', '--test', '--consumer-ui']),
        ('collection_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_collection_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('collection_restriction', ['--fixed-fps', '60', '--script', 'res://tools/test_collection_restriction.gd', '--', '--test', '--consumer-ui']),
        ('collection_restriction_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_collection_restriction_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('collection_accessibility', ['--fixed-fps', '60', '--script', 'res://tools/test_collection_accessibility.gd', '--', '--test', '--consumer-ui']),
        ('collection_portable', ['--fixed-fps', '60', '--script', 'res://tools/test_collection_portable.gd', '--', '--test', '--consumer-ui']),
        ('character_actions', ['--fixed-fps', '60', '--script', 'res://tools/test_character_actions.gd', '--', '--test']),
        ('animation_import_metadata', ['--fixed-fps', '60', '--script', 'res://tools/test_animation_import_metadata.gd', '--', '--test']),
        ('supplemental_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_supplemental_assets.gd']),
        ('supplemental_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_supplemental_workflow.gd']),
        ('swat_pack', ['--fixed-fps', '60', '--script', 'res://tools/test_swat_pack.gd']),
        ('consumer_ui', ['--fixed-fps', '60', '--script', 'res://tools/test_consumer_ui.gd', '--', '--consumer-ui']),
        ('weather_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_weather_foundation.gd', '--', '--test']),
        ('props_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_props_foundation.gd', '--', '--test']),
        ('driving_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_driving_foundation.gd', '--', '--test']),
        ('driving_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_driving_workflow.gd', '--', '--test']),
        ('driving_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_driving_export_runtime.gd', '--', '--2d']),
        ('driving_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_driving_export_runtime.gd', '--', '--3d']),
        ('creation_share', ['--fixed-fps', '60', '--script', 'res://tools/test_creation_share.gd', '--', '--test']),
        ('creation_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_creation_workflow.gd', '--', '--test']),
        ('cooperative_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_cooperative_foundation.gd', '--', '--test']),
        ('cooperative_district_batch', ['--fixed-fps', '60', '--script', 'res://tools/test_cooperative_district_batch.gd', '--', '--test']),
        ('cooperative_protection', ['--fixed-fps', '60', '--script', 'res://tools/test_cooperative_protection.gd', '--', '--test']),
        ('cooperative_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_cooperative_workflow.gd', '--', '--test']),
        ('cooperative_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_cooperative_export_runtime.gd', '--', '--2d']),
        ('cooperative_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_cooperative_export_runtime.gd', '--', '--3d']),
        ('asset_import_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_import_foundation.gd', '--', '--test']),
        ('asset_import_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_import_workflow.gd', '--', '--test']),
        ('asset_import_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_import_export_runtime.gd', '--', '--2d']),
        ('asset_import_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_import_export_runtime.gd', '--', '--3d']),
        ('asset_import_shutdown_sprite', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_import_shutdown.gd', '--', '--test', '--sprite']),
        ('asset_import_shutdown_model', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_import_shutdown.gd', '--', '--test']),
        ('modular_sockets', ['--fixed-fps', '60', '--script', 'res://tools/test_modular_sockets.gd', '--', '--test']),
        ('modular_sockets_simple', ['--fixed-fps', '60', '--script', 'res://tools/test_modular_sockets.gd', '--', '--test', '--consumer-ui']),
        ('modular_sockets_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_modular_sockets_cooperative.gd', '--', '--test']),
        ('water_network', ['--fixed-fps', '60', '--script', 'res://tools/test_water_network.gd', '--', '--test', '--consumer-ui']),
        ('water_network_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_water_network_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('power_network', ['--fixed-fps', '60', '--script', 'res://tools/test_power_network.gd', '--', '--test', '--consumer-ui']),
        ('power_network_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_power_network_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('connection_affordances', ['--fixed-fps', '60', '--script', 'res://tools/test_connection_affordances.gd', '--', '--test', '--consumer-ui']),
        ('connection_affordances_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_connection_affordances_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('blueprint_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_blueprint_foundation.gd', '--', '--test']),
        ('blueprint_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_blueprint_workflow.gd', '--', '--test']),
        ('functional_assemblies', ['--fixed-fps', '60', '--script', 'res://tools/test_functional_assemblies.gd', '--', '--test']),
        ('functional_assembly_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_functional_assembly_cooperative.gd', '--', '--consumer-ui']),
        ('blueprint_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_blueprint_export_runtime.gd', '--', '--2d']),
        ('blueprint_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_blueprint_export_runtime.gd', '--', '--3d']),
        ('photo_foundation', ['--fixed-fps', '60', '--script', 'res://tools/test_photo_foundation.gd', '--', '--test']),
        ('photo_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_photo_workflow.gd', '--', '--test']),
        ('photo_interactions', ['--fixed-fps', '60', '--script', 'res://tools/test_photo_interactions.gd', '--', '--test']),
        ('photo_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_photo_export_runtime.gd', '--', '--2d']),
        ('photo_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_photo_export_runtime.gd', '--', '--3d']),
        ('props_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_props_workflow.gd', '--', '--test']),
        ('interaction_setup_plan', ['--fixed-fps', '60', '--script', 'res://tools/test_interaction_setup_plan.gd', '--', '--test']),
        ('interaction_setup_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_interaction_setup_workflow.gd', '--', '--consumer-ui']),
        ('interaction_setup_precision', ['--fixed-fps', '60', '--script', 'res://tools/test_interaction_setup_workflow.gd', '--', '--test']),
        ('interaction_setup_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_interaction_setup_cooperative.gd', '--', '--consumer-ui']),
        ('props_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_props_export_runtime.gd', '--', '--2d']),
        ('props_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_props_export_runtime.gd', '--', '--3d']),
        ('weather_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_weather_workflow.gd', '--', '--test']),
        ('weather_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_weather_export_runtime.gd', '--', '--2d']),
        ('weather_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_weather_export_runtime.gd', '--', '--3d']),
        ('features', ['--script', 'res://tools/test_main_features.gd']),
        ('studio', ['--script', 'res://tools/test_studio.gd', '--', '--test']),
        ('upgrade', ['--script', 'res://tools/test_studio_upgrade.gd', '--', '--test']),
        ('mixed', ['--script', 'res://tools/test_mixed_assets.gd', '--', '--test']),
        ('precision', ['--script', 'res://tools/test_precision_editing.gd', '--', '--test']),
        ('compass', ['--script', 'res://tools/test_compass_rotation.gd', '--', '--test']),
        ('alignment', ['--script', 'res://tools/test_alignment.gd', '--', '--test']),
        ('library_grid', ['--script', 'res://tools/test_library_grid.gd', '--', '--test']),
        ('tile_paint', ['--script', 'res://tools/test_tile_paint.gd', '--', '--test']),
        ('editor_foundations', ['--script', 'res://tools/test_editor_foundations.gd', '--', '--test']),
        ('exploration_motion', ['--script', 'res://tools/test_exploration_motion.gd', '--', '--test']),
        ('entrance_anchors', ['--script', 'res://tools/test_entrance_anchors.gd', '--', '--test']),
        ('persistent_interiors', ['--script', 'res://tools/test_persistent_interiors.gd', '--', '--test']),
        ('project_recovery', ['--script', 'res://tools/test_project_recovery.gd', '--', '--test']),
        ('project_repair', ['--script', 'res://tools/test_project_repair.gd', '--', '--test']),
        ('appearance_selection', ['--script', 'res://tools/test_appearance_selection.gd', '--', '--test']),
        ('ground_roads', ['--script', 'res://tools/test_ground_roads.gd', '--', '--test']),
        ('arrange', ['--script', 'res://tools/test_arrange_tools.gd', '--', '--test']),
        ('editor_workflow', ['--script', 'res://tools/test_editor_workflow.gd', '--', '--test']),
        ('workspace_layout', ['--script', 'res://tools/test_workspace_layout.gd', '--', '--test']),
        ('selection_inspector', ['--script', 'res://tools/test_selection_inspector.gd', '--', '--test']),
        ('asset_browser', ['--script', 'res://tools/test_asset_browser.gd', '--', '--test']),
        ('overlap_picker', ['--script', 'res://tools/test_overlap_picker.gd', '--', '--test']),
        ('small_prop_view', ['--fixed-fps', '60', '--script', 'res://tools/test_small_prop_view.gd', '--', '--test', '--consumer-ui']),
        ('small_prop_scopes', ['--fixed-fps', '60', '--script', 'res://tools/test_small_prop_scopes.gd', '--', '--test', '--consumer-ui']),
        ('small_prop_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_small_prop_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('small_prop_exports', ['--fixed-fps', '60', '--script', 'res://tools/test_small_prop_exports.gd', '--', '--test', '--consumer-ui']),
        ('editor_feedback', ['--script', 'res://tools/test_editor_feedback.gd', '--', '--test']),
        ('workspace_presets', ['--script', 'res://tools/test_workspace_presets.gd', '--', '--test']),
        ('control_settings', ['--script', 'res://tools/test_control_settings.gd', '--', '--test']),
        ('accessibility', ['--script', 'res://tools/test_accessibility.gd', '--', '--test']),
        ('first_build', ['--script', 'res://tools/test_first_build.gd', '--', '--test']),
        ('transform_handles', ['--script', 'res://tools/test_transform_handles.gd', '--', '--test']),
        ('citizen_plan', ['--script', 'res://tools/test_citizen_plan.gd', '--', '--test']),
        ('citizen_obstacles_2d', ['--script', 'res://tools/test_citizen_obstacles_2d.gd', '--', '--test']),
        ('citizen_runtime', ['--script', 'res://tools/test_citizen_runtime.gd', '--', '--test']),
        ('school_life', ['--fixed-fps', '60', '--script', 'res://tools/test_school_life.gd', '--', '--test', '--stress', '--consumer-ui']),
        ('school_bus', ['--fixed-fps', '60', '--script', 'res://tools/test_school_bus.gd', '--', '--test', '--packages']),
        ('school_crossing', ['--fixed-fps', '60', '--script', 'res://tools/test_school_crossing.gd', '--', '--test']),
        ('school_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_school_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('vehicle_care', ['--fixed-fps', '60', '--script', 'res://tools/test_vehicle_care.gd', '--', '--test', '--stress', '--packages']),
        ('vehicle_care_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_vehicle_care_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('local_deliveries', ['--fixed-fps', '60', '--script', 'res://tools/test_local_deliveries.gd', '--', '--test', '--packages', '--edges']),
        ('local_delivery_traffic', ['--fixed-fps', '60', '--script', 'res://tools/test_delivery_traffic.gd', '--', '--test']),
        ('local_deliveries_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_local_deliveries_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('construction_contracts', ['--fixed-fps', '60', '--script', 'res://tools/test_construction_contracts.gd', '--', '--test', '--consumer-ui', '--edges', '--packages']),
        ('construction_contract_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_construction_contract_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('market_days', ['--fixed-fps', '60', '--script', 'res://tools/test_market_days.gd', '--', '--test', '--packages']),
        ('market_deliveries', ['--fixed-fps', '60', '--script', 'res://tools/test_market_deliveries.gd', '--', '--test']),
        ('market_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_market_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('resident_activity_plan', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_plan.gd', '--', '--test']),
        ('resident_activities', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activities.gd', '--', '--test']),
        ('resident_activity_defaults', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_defaults.gd', '--', '--test']),
        ('resident_activity_view', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_view.gd', '--', '--test']),
        ('resident_activity_routines', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_routines.gd', '--', '--consumer-ui']),
        ('resident_activity_cafe', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_cafe.gd', '--', '--consumer-ui']),
        ('resident_activity_lifecycle', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_lifecycle.gd', '--', '--consumer-ui']),
        ('resident_activity_destruction', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_destruction.gd', '--', '--consumer-ui']),
        ('resident_activity_interruptions', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_interruptions.gd', '--', '--consumer-ui']),
        ('resident_activity_navigation_refresh', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_navigation_refresh.gd', '--', '--consumer-ui']),
        ('resident_activity_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_cooperative.gd', '--', '--consumer-ui']),
        ('resident_activity_support', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_support.gd', '--', '--consumer-ui']),
        ('resident_activity_raised', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_raised.gd', '--', '--consumer-ui']),
        ('resident_activity_controls', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_controls.gd', '--', '--consumer-ui']),
        ('resident_activity_controls_precision', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_controls.gd', '--', '--test']),
        ('resident_activity_controls_layout', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_controls_layout.gd', '--', '--consumer-ui']),
        ('resident_activity_settings_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_settings_cooperative.gd', '--', '--consumer-ui']),
        ('resident_activity_copy_scope', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_copy_scope.gd', '--', '--consumer-ui']),
        ('resident_activity_room_layout', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_room_layout.gd', '--', '--consumer-ui']),
        ('resident_activity_cafe_room_layout', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_cafe_room_layout.gd', '--', '--consumer-ui']),
        ('resident_activity_exports', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_activity_exports.gd', '--', '--consumer-ui']),
        ('resident_floor_capacity', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_floor_capacity.gd', '--', '--test']),
        ('resident_elevator_passenger', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_passenger.gd', '--', '--test']),
        ('resident_elevator_routines', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_routines.gd', '--', '--consumer-ui']),
        ('resident_elevator_offset', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_offset.gd', '--', '--consumer-ui']),
        ('resident_elevator_context', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_context.gd', '--', '--consumer-ui']),
        ('resident_elevator_context_delay', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_context_delay.gd', '--', '--consumer-ui']),
        ('resident_elevator_context_closing', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_context_closing.gd', '--', '--consumer-ui']),
        ('resident_elevator_context_opening', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_context_opening.gd', '--', '--consumer-ui']),
        ('resident_elevator_context_descending', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_context_descending.gd', '--', '--consumer-ui']),
        ('resident_elevator_first_visit', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_first_visit.gd', '--', '--consumer-ui']),
        ('resident_elevator_first_boarding', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_first_boarding.gd', '--', '--consumer-ui']),
        ('resident_elevator_first_call', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_first_call.gd', '--', '--consumer-ui']),
        ('resident_elevator_middle', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_middle.gd', '--', '--consumer-ui']),
        ('resident_stair_routines', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_routines.gd', '--', '--consumer-ui']),
        ('resident_stair_capacity', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_capacity.gd', '--', '--consumer-ui']),
        ('resident_stair_context', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_context.gd', '--', '--consumer-ui']),
        ('resident_stair_context_delay', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_context_delay.gd', '--', '--consumer-ui']),
        ('resident_stair_context_descending', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_context_descending.gd', '--', '--consumer-ui']),
        ('resident_stair_obstruction', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_obstruction.gd', '--', '--consumer-ui']),
        ('resident_stair_first_visit', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_first_visit.gd', '--', '--consumer-ui']),
        ('resident_stair_terrain', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_stair_terrain.gd', '--', '--consumer-ui']),
        ('floor_stairs_slow', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_stairs_slow.gd', '--', '--consumer-ui']),
        ('resident_elevator_context_calling', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_context_calling.gd', '--', '--consumer-ui']),
        ('resident_elevator_context_alighting', ['--fixed-fps', '60', '--script', 'res://tools/test_resident_elevator_context_alighting.gd', '--', '--consumer-ui']),
        ('floor_platform_collisions', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_platform_collisions.gd', '--', '--test']),
        ('citizen_neighborhood', ['--script', 'res://tools/test_citizen_neighborhood.gd', '--', '--test']),
        ('traffic_plan', ['--script', 'res://tools/test_traffic_plan.gd', '--', '--test']),
        ('traffic_controls', ['--fixed-fps', '60', '--script', 'res://tools/test_traffic_controls.gd', '--', '--test']),
        ('traffic_controls_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_traffic_controls_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('traffic_four_way_runtime', ['--fixed-fps', '60', '--script', 'res://tools/test_traffic_four_way_runtime.gd', '--', '--test']),
        ('fleet_profiles', ['--fixed-fps', '60', '--script', 'res://tools/test_fleet_profiles.gd', '--', '--test', '--packages']),
        ('fleet_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_fleet_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('traffic_reroute', ['--fixed-fps', '60', '--script', 'res://tools/test_traffic_reroute.gd', '--', '--test', '--packages']),
        ('traffic_reroute_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_traffic_reroute_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('traffic_runtime', ['--script', 'res://tools/test_traffic_runtime.gd', '--', '--test']),
        ('business_plan', ['--script', 'res://tools/test_business_plan.gd', '--', '--test']),
        ('business_runtime', ['--script', 'res://tools/test_business_runtime.gd', '--', '--test']),
        ('service_plan', ['--script', 'res://tools/test_service_plan.gd', '--', '--test']),
        ('service_runtime', ['--script', 'res://tools/test_service_runtime.gd', '--', '--test']),
        ('service_workflow', ['--script', 'res://tools/test_service_workflow.gd', '--', '--test']),
        ('economy_plan', ['--script', 'res://tools/test_economy_plan.gd', '--', '--test']),
        ('economy_workflow', ['--script', 'res://tools/test_economy_workflow.gd', '--', '--test']),
        ('construction_costs', ['--fixed-fps', '60', '--script', 'res://tools/test_construction_costs.gd', '--', '--test', '--consumer-ui']),
        ('construction_costs_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_construction_costs_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('scenario_plan', ['--script', 'res://tools/test_scenario_plan.gd', '--', '--test']),
        ('scenario_workflow', ['--script', 'res://tools/test_scenario_workflow.gd', '--', '--test']),
        ('emergency_training_plan', ['--script', 'res://tools/test_emergency_training_plan.gd', '--', '--test']),
        ('emergency_training_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_emergency_training_workflow.gd', '--', '--test', '--consumer-ui']),
        ('emergency_training_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_emergency_training_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('space_outpost_plan', ['--script', 'res://tools/test_space_outpost_plan.gd', '--', '--test']),
        ('space_outpost_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_space_outpost_workflow.gd', '--', '--test', '--consumer-ui']),
        ('space_outpost_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_space_outpost_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('asset_expansion_golden', ['--script', 'res://tools/test_asset_expansion_golden.gd', '--', '--test', '--packages']),
        ('asset_expansion_defaults', ['--fixed-fps', '60', '--script', 'res://tools/test_asset_expansion_defaults.gd', '--', '--test']),
        ('zone_plan', ['--script', 'res://tools/test_zone_plan.gd', '--', '--test']),
        ('zone_candidates', ['--script', 'res://tools/test_zone_candidates.gd', '--', '--test']),
        ('zone_expansion', ['--script', 'res://tools/test_zone_expansion.gd', '--', '--test']),
        ('zone_designs', ['--fixed-fps', '60', '--script', 'res://tools/test_zone_designs.gd', '--', '--test']),
        ('zone_candidate_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_zone_candidate_workflow.gd', '--', '--test', '--consumer-ui']),
        ('zone_expansion_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_zone_expansion_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('zone_export_policy', ['--script', 'res://tools/test_zone_export_policy.gd', '--', '--test']),
        ('export_source_precision', ['--script', 'res://tools/test_export_source_precision.gd', '--', '--test']),
        ('zone_workflow', ['--script', 'res://tools/test_zone_workflow.gd', '--', '--test']),
        ('simulation_diagnostics', ['--fixed-fps', '60', '--script', 'res://tools/test_simulation_diagnostics.gd', '--', '--test', '--consumer-ui', '--packages']),
        ('simulation_diagnostics_jobs', ['--fixed-fps', '60', '--script', 'res://tools/test_simulation_diagnostics_jobs.gd', '--', '--test', '--consumer-ui']),
        ('simulation_diagnostics_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_simulation_diagnostics_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('construction_stages', ['--fixed-fps', '60', '--script', 'res://tools/test_construction_stages.gd', '--', '--test', '--consumer-ui', '--packages']),
        ('zone_theme_export', ['--fixed-fps', '60', '--script', 'res://tools/test_zone_theme_export.gd', '--', '--test']),
        ('transit_plan', ['--script', 'res://tools/test_transit_plan.gd', '--', '--test']),
        ('transit_runtime', ['--script', 'res://tools/test_transit_runtime.gd', '--', '--test']),
        ('transit_workflow', ['--script', 'res://tools/test_transit_workflow.gd', '--', '--test']),
        ('terrain_plan', ['--script', 'res://tools/test_terrain_plan.gd', '--', '--test']),
        ('neighborhood_plan', ['--script', 'res://tools/test_neighborhood_plan.gd', '--', '--test']),
        ('neighborhood_palettes', ['--script', 'res://tools/test_neighborhood_palettes.gd', '--', '--test']),
        ('neighborhood_theme_edges', ['--script', 'res://tools/test_neighborhood_theme_edges.gd', '--', '--test']),
        ('neighborhood_theme_physics', ['--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_theme_physics.gd', '--', '--test']),
        ('neighborhood_theme_dependencies', ['--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_theme_dependencies.gd', '--', '--test', '--consumer-ui']),
        ('neighborhood_theme_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_theme_workflow.gd', '--', '--test', '--consumer-ui']),
        ('neighborhood_theme_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_theme_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('ambience_plan', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_ambience_plan.gd', '--', '--test']),
        ('ambience_runtime', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_ambience_runtime.gd', '--', '--test']),
        ('place_ambience', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_place_ambience.gd', '--', '--test', '--consumer-ui', '--portable']),
        ('school_ambience', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_school_ambience.gd', '--', '--test', '--consumer-ui']),
        ('place_ambience_cooperative', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_place_ambience_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('ambience_workflow', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_ambience_workflow.gd', '--', '--test']),
        ('ambience_export_2d', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_ambience_export_runtime.gd', '--', '--2d']),
        ('ambience_export_3d', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_ambience_export_runtime.gd', '--', '--3d']),
        ('neighborhood_foundation', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_foundation.gd', '--', '--test']),
        ('neighborhood_workflow', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_workflow.gd', '--', '--test']),
        ('neighborhood_theme_exports', ['--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_theme_exports.gd', '--', '--test']),
        ('neighborhood_export_2d', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_export_runtime.gd', '--', '--2d']),
        ('neighborhood_export_3d', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_neighborhood_export_runtime.gd', '--', '--3d']),
        ('floor_plan', ['--script', 'res://tools/test_floor_plan.gd', '--', '--test']),
        ('floor_workflow', ['--script', 'res://tools/test_floor_workflow.gd', '--', '--test']),
        ('floor_nested_history', ['--script', 'res://tools/test_floor_nested_history.gd', '--', '--test']),
        ('floor_marker_history', ['--script', 'res://tools/test_floor_marker_history.gd', '--', '--test']),
        ('floor_maximum', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_floor_maximum.gd', '--', '--test']),
        ('floor_maximum_export_2d', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_floor_maximum_export_runtime.gd', '--', '--2d']),
        ('floor_maximum_export_3d', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://tools/test_floor_maximum_export_runtime.gd', '--', '--3d']),
        ('floor_stairs_3d', ['--script', 'res://tools/test_floor_stairs_3d.gd', '--', '--test']),
        ('floor_stairs_export', ['--script', 'res://tools/test_floor_stairs_export_runtime.gd', '--', '--local']),
        ('floor_connections', ['--script', 'res://tools/test_floor_connections.gd', '--', '--test']),
        ('floor_connections_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_connections_export_runtime.gd', '--', '--2d']),
        ('floor_connections_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_connections_export_runtime.gd', '--', '--3d']),
        ('floor_elevator_plan', ['--script', 'res://tools/test_floor_elevator_plan.gd', '--', '--test']),
        ('floor_elevator_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_elevator_3d.gd', '--', '--test']),
        ('floor_elevator_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_elevator_workflow.gd', '--', '--test']),
        ('floor_elevator_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_elevator_export_runtime.gd', '--', '--2d']),
        ('floor_elevator_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_elevator_export_runtime.gd', '--', '--3d']),
        ('floor_entrances', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_entrances.gd', '--', '--test']),
        ('floor_entrances_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_entrances_export_runtime.gd', '--', '--2d']),
        ('floor_entrances_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_entrances_export_runtime.gd', '--', '--3d']),
        ('floor_editor_walk', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_editor_walk.gd', '--', '--test']),
        ('floor_editor_walk_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_editor_walk_export_runtime.gd', '--', '--2d']),
        ('floor_editor_walk_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_editor_walk_export_runtime.gd', '--', '--3d']),
        ('floor_terrain', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_terrain.gd', '--', '--test']),
        ('floor_terrain_recovery', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_terrain_recovery.gd', '--', '--test']),
        ('floor_terrain_export_2d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_terrain_export_runtime.gd', '--', '--2d']),
        ('floor_terrain_export_3d', ['--fixed-fps', '60', '--script', 'res://tools/test_floor_terrain_export_runtime.gd', '--', '--3d']),
        ('terrain_geometry', ['--script', 'res://tools/test_terrain_geometry.gd', '--', '--test']),
        ('terrain_2d', ['--script', 'res://tools/test_terrain_2d.gd', '--', '--test']),
        ('terrain_world_3d', ['--script', 'res://tools/test_terrain_world_3d.gd', '--', '--test']),
        ('terrain_tiles_2d', ['--script', 'res://tools/test_terrain_tiles_2d.gd', '--', '--test']),
        ('connected_terrain', ['--fixed-fps', '60', '--script', 'res://tools/test_connected_terrain.gd', '--', '--test', '--consumer-ui']),
        ('harbor_plan', ['--script', 'res://tools/test_harbor_plan.gd', '--', '--test']),
        ('harbor_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_harbor_workflow.gd', '--', '--test', '--consumer-ui']),
        ('harbor_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_harbor_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('connected_terrain_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_connected_terrain_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('modular_building_plan', ['--fixed-fps', '60', '--script', 'res://tools/test_modular_building_plan.gd']),
        ('modular_building_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_modular_building_workflow.gd', '--', '--test', '--consumer-ui']),
        ('modular_building_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_modular_building_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('garden_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_garden.gd', '--', '--test', '--consumer-ui']),
        ('garden_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_garden_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('cooking_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_cooking.gd', '--', '--test', '--consumer-ui']),
        ('cooking_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_cooking_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('laundry_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_laundry.gd', '--', '--test', '--consumer-ui']),
        ('laundry_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_laundry_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('fitness_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_fitness.gd', '--', '--test', '--consumer-ui']),
        ('fitness_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_fitness_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('arcade_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_arcade.gd', '--', '--test', '--consumer-ui']),
        ('arcade_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_arcade_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('camping_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_camping.gd', '--', '--test', '--consumer-ui']),
        ('camping_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_camping_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('pet_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_pet.gd', '--', '--test', '--consumer-ui']),
        ('pet_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_pet_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('cycling_workflow', ['--fixed-fps', '60', '--script', 'res://tools/test_cycling.gd', '--', '--test', '--consumer-ui']),
        ('cycling_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_cycling_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('village_production', ['--fixed-fps', '60', '--script', 'res://tools/test_village_production.gd', '--', '--test', '--consumer-ui']),
        ('village_cooperative', ['--fixed-fps', '60', '--script', 'res://tools/test_village_production_cooperative.gd', '--', '--test', '--consumer-ui']),
        ('terrain_presentation_2d', ['--script', 'res://tools/test_terrain_presentation_2d.gd', '--', '--test']),
        ('terrain_workflow', ['--script', 'res://tools/test_terrain_workflow.gd', '--', '--test']),
        ('terrain_traversal', ['--fixed-fps', '60', '--script', 'res://tools/test_terrain_traversal.gd', '--', '--test']),
        ('terrain_navigation', ['--fixed-fps', '60', '--script', 'res://tools/test_terrain_navigation.gd', '--', '--test']),
        ('terrain_roads', ['--script', 'res://tools/test_terrain_roads.gd', '--', '--test']),
        ('terrain_traffic', ['--script', 'res://tools/test_terrain_traffic.gd', '--', '--test']),
        ('terrain_parking', ['--script', 'res://tools/test_terrain_parking.gd', '--', '--test']),
        ('terrain_services', ['--fixed-fps', '60', '--script', 'res://tools/test_terrain_services.gd', '--', '--test']),
        ('terrain_transit', ['--fixed-fps', '60', '--script', 'res://tools/test_terrain_transit.gd', '--', '--test']),
        ('terrain_zoning', ['--script', 'res://tools/test_terrain_zoning.gd', '--', '--test']),
        ('terrain_spawn', ['--fixed-fps', '60', '--script', 'res://tools/test_terrain_spawn.gd', '--', '--test']),
        ('terrain_editor_feedback', ['--script', 'res://tools/test_terrain_editor_feedback.gd', '--', '--test']),
        ('terrain_authoring', ['--script', 'res://tools/test_terrain_authoring.gd', '--', '--test']),
        ('added', ['--script', 'res://tools/test_added_assets.gd', '--', '--test']),
    ]
    logs = ROOT / 'output' / 'verification'
    logs.mkdir(parents=True, exist_ok=True)
    if '--from-check' in sys.argv:
        start = sys.argv[sys.argv.index('--from-check') + 1]
        checks = checks[[name for name, _ in checks].index(start):]
    for name, arguments in ([] if portable_start else checks):
        # Full inventory checks can take longer immediately after the editor import.
        timeout = {'assets': 300, 'library_grid': 900}.get(name, 180)
        result = subprocess.run(
            [godot, '--headless', '--path', str(ROOT), *arguments],
            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding='utf-8', errors='replace', timeout=timeout)
        (logs / f'{name}.log').write_text(result.stdout, encoding='utf-8')
        errors = re.search(r'(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING: .*were leaked at exit)', result.stdout)
        if result.returncode or errors:
            print(result.stdout)
            print(f'FAILED: {name} (exit {result.returncode}). See {logs / (name + ".log")}', file=sys.stderr)
            return 1
        summaries = [line for line in result.stdout.splitlines()
                     if line.startswith(('ASSETS:', 'MAIN FEATURES:', 'STUDIO:', 'STUDIO UPGRADE:', 'MIXED ASSETS:', 'PRECISION EDITING:', 'COMPASS:', 'ALIGNMENT:', 'LIBRARY GRID:', 'TILE PAINT:', 'ADDED ASSETS:', 'EDITOR FOUNDATIONS:', 'EDITOR WORKFLOW:', 'WORKSPACE LAYOUT:', 'ARRANGE TOOLS:', 'GROUND / ROADS:', 'APPEARANCE / SELECTION:', 'EXPLORATION MOTION:', 'ENTRANCE ANCHORS:', 'PERSISTENT INTERIORS:', 'PROJECT RECOVERY:', 'PROJECT REPAIR:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('Creation sharing:', 'Creation workflow:', 'Cooperative foundation:', 'Cooperative protection:', 'Cooperative workflow:', 'Cooperative export:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('SELECTION INSPECTOR:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('DRIVING FOUNDATION:', 'DRIVING WORKFLOW:', 'DRIVING EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('PHOTO FOUNDATION:', 'PHOTO WORKFLOW:', 'PHOTO INTERACTIONS:', 'PHOTO EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('ASSET BROWSER:', 'GOLDEN SCENARIOS:', 'ASSET EXPANSION DEFAULTS:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('OVERLAP PICKER:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('EDITOR FEEDBACK:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('WORKSPACE PRESETS:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('CONTROL SETTINGS:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('ACCESSIBILITY:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('FIRST BUILD:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TRANSFORM HANDLES:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('CITIZEN PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('CITIZEN RUNTIME:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('CITIZEN NEIGHBORHOOD:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TRAFFIC PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TRAFFIC RUNTIME:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('BUSINESS PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('BUSINESS RUNTIME:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('SERVICE PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('SERVICE RUNTIME:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('SERVICE WORKFLOW:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('ECONOMY PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('ECONOMY WORKFLOW:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('SCENARIO PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('SCENARIO WORKFLOW:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('ZONE PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('ZONE WORKFLOW:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TRANSIT PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TRANSIT RUNTIME:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TRANSIT WORKFLOW:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN PLAN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('NEIGHBORHOOD PLAN:', 'NEIGHBORHOOD FOUNDATION:', 'NEIGHBORHOOD WORKFLOW:', 'NEIGHBORHOOD EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('AMBIENCE PLAN:', 'AMBIENCE RUNTIME:', 'AMBIENCE WORKFLOW:', 'AMBIENCE EXPORT:', 'PLACE AMBIENCE:', 'SCHOOL AMBIENCE:', 'PLACE AMBIENCE COOPERATIVE:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('WEATHER FOUNDATION:', 'WEATHER WORKFLOW:', 'WEATHER EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('PROPS FOUNDATION:', 'PROPS WORKFLOW:', 'PROPS EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('FLOOR PLAN:', 'FLOOR WORKFLOW:', 'FLOOR STAIRS 3D:', 'FLOOR STAIRS EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('FLOOR MAXIMUM:', 'FLOOR MAXIMUM EXPORT:', 'FLOOR NESTED HISTORY:', 'FLOOR MARKER HISTORY:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('FLOOR ENTRANCES:', 'FLOOR ENTRANCES EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('FLOOR EDITOR WALK:', 'FLOOR EDITOR WALK EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('FLOOR TERRAIN:', 'FLOOR TERRAIN EXPORT:', 'FLOOR TERRAIN RECOVERY:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('FLOOR CONNECTIONS:', 'FLOOR CONNECTIONS EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith(('FLOOR ELEVATOR PLAN:', 'FLOOR ELEVATOR 3D:', 'FLOOR ELEVATOR WORKFLOW:', 'FLOOR ELEVATOR EXPORT:'))]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN GEOMETRY:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN 2D:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN WORLD 3D:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN TILES 2D:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN PRESENTATION 2D:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN WORKFLOW:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN TRAVERSAL:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN NAVIGATION:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN ROADS:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN TRAFFIC:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN PARKING:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN SERVICES:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN TRANSIT:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN ZONING:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN SPAWN:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN EDITOR FEEDBACK:')]
        summaries += [line for line in result.stdout.splitlines() if line.startswith('TERRAIN AUTHORING:')]
        print(f'PASS: {name}' + (' - ' + ' '.join(summaries) if summaries else ''))
    portable_started = portable_start is None

    def run_portable(command, **options):
        nonlocal portable_started
        name = Path(command[2]).stem
        for flag in ('--diagnostics', '--village', '--themes', '--place'):
            if flag in command:
                name += ':' + flag[2:]
        if not portable_started and name != portable_start:
            return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
        portable_started = True
        print(f'RUN PORTABLE: {name}', flush=True)
        requested_capture = options.get('capture_output', False)
        if os.name == 'nt':
            options.update(capture_output=True, text=True, encoding='utf-8', errors='replace')
        result = subprocess.run(command, **options)
        if os.name == 'nt':
            # Each verifier creates a fresh relocation directory on every invocation.
            if result.returncode and 'import verification failed (process exit 3221225477)' in (result.stderr or ''):
                print(result.stdout or '', end='', flush=True)
                print(result.stderr or '', end='', file=sys.stderr, flush=True)
                print(f'RETRY PORTABLE: {name} after a Windows editor import access violation', flush=True)
                result = subprocess.run(command, **options)
            if not requested_capture:
                print(result.stdout or '', end='', flush=True)
                print(result.stderr or '', end='', file=sys.stderr, flush=True)
        if result.returncode:
            print(f'FAILED PORTABLE: {name} (exit {result.returncode})', file=sys.stderr, flush=True)
        else:
            print(f'PASS PORTABLE: {name}', flush=True)
        return result

    portable = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_portable.py')], cwd=ROOT)
    if portable.returncode:
        return portable.returncode
    citizens = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_citizen_portable.py')], cwd=ROOT)
    if citizens.returncode:
        return citizens.returncode
    traffic = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_traffic_portable.py')], cwd=ROOT)
    if traffic.returncode:
        return traffic.returncode
    fleet = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_fleet_portable.py'), str(ROOT / 'output' / 'fleet_fixture')], cwd=ROOT)
    if fleet.returncode:
        return fleet.returncode
    reroute = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_traffic_reroute_portable.py'),
        str(ROOT / 'output' / 'reroute_fixture'), *(['--visible-import'] if os.name == 'nt' else [])], cwd=ROOT)
    if reroute.returncode:
        return reroute.returncode
    diagnostics = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_traffic_reroute_portable.py'),
                                  str(ROOT / 'output' / 'simulation_diagnostics_fixture'), '--diagnostics',
                                  *(['--visible-import'] if os.name == 'nt' else [])], cwd=ROOT)
    if diagnostics.returncode:
        return diagnostics.returncode
    schools = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_school_portable.py'), str(ROOT / 'output' / 'school_fixture')], cwd=ROOT)
    if schools.returncode:
        return schools.returncode
    vehicle_care = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_vehicle_care_portable.py'), str(ROOT / 'output' / 'vehicle_care_fixture')], cwd=ROOT)
    if vehicle_care.returncode:
        return vehicle_care.returncode
    deliveries = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_local_delivery_portable.py'), str(ROOT / 'output' / 'delivery_fixture'),
                                 *(['--visible-import'] if os.name == 'nt' else [])], cwd=ROOT)
    if deliveries.returncode:
        return deliveries.returncode
    contracts = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_construction_contract_portable.py'),
                                str(ROOT / 'output' / 'construction_contract_fixture'), *(['--visible-import'] if os.name == 'nt' else [])], cwd=ROOT)
    if contracts.returncode:
        return contracts.returncode
    markets = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_market_portable.py'), str(ROOT / 'output' / 'market_fixture'),
                               *(['--visible-import'] if os.name == 'nt' else [])], cwd=ROOT)
    if markets.returncode:
        return markets.returncode
    businesses = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_business_portable.py')], cwd=ROOT)
    if businesses.returncode:
        return businesses.returncode
    services = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_service_portable.py')], cwd=ROOT)
    if services.returncode:
        return services.returncode
    economy = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_economy_portable.py')], cwd=ROOT)
    if economy.returncode:
        return economy.returncode
    scenarios = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_scenario_portable.py')], cwd=ROOT)
    if scenarios.returncode:
        return scenarios.returncode
    for gate in ('verify_cooperative_processes.py', 'verify_cooperative_portable.py'):
        cooperative = run_portable([sys.executable, '-u', str(ROOT / 'tools' / gate)], cwd=ROOT,
                                     capture_output=True, text=True, encoding='utf-8', errors='replace')
        if not portable_started:
            continue
        (logs / (Path(gate).stem + '.log')).write_text(cooperative.stdout + cooperative.stderr, encoding='utf-8')
        print(cooperative.stdout, end='')
        if cooperative.returncode:
            print(cooperative.stderr, file=sys.stderr)
            return cooperative.returncode
    custom_import = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_asset_import_portable.py')], cwd=ROOT)
    if custom_import.returncode:
        return custom_import.returncode
    for verifier in ('verify_construction_costs_portable.py', 'verify_harbor_portable.py', 'verify_emergency_training_portable.py', 'verify_space_outpost_portable.py'):
        feature = run_portable([sys.executable, '-u', str(ROOT / 'tools' / verifier)], cwd=ROOT)
        if feature.returncode:
            return feature.returncode
    blueprint = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_blueprint_portable.py')], cwd=ROOT)
    if blueprint.returncode:
        return blueprint.returncode
    zoning = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_zone_portable.py'),
        *(['--visible-import', '--import-accessibility-dummy'] if os.name == 'nt' else [])], cwd=ROOT)
    if zoning.returncode:
        return zoning.returncode
    zoning_village = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_zone_portable.py'), '--village',
        *(['--visible-import', '--import-accessibility-dummy'] if os.name == 'nt' else [])], cwd=ROOT)
    if zoning_village.returncode:
        return zoning_village.returncode
    construction = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_construction_stages_portable.py'),
        str(ROOT / 'output' / 'construction_stages_fixture'), *(['--visible-import'] if os.name == 'nt' else [])], cwd=ROOT)
    if construction.returncode:
        return construction.returncode
    transit = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_transit_portable.py')], cwd=ROOT)
    if transit.returncode:
        return transit.returncode
    terrain = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_terrain_portable.py')], cwd=ROOT)
    if terrain.returncode:
        return terrain.returncode
    terrain_traffic = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_terrain_traffic_portable.py')], cwd=ROOT)
    if terrain_traffic.returncode:
        return terrain_traffic.returncode
    terrain_services = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_terrain_service_portable.py')], cwd=ROOT)
    if terrain_services.returncode:
        return terrain_services.returncode
    terrain_transit = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_terrain_transit_portable.py')], cwd=ROOT)
    if terrain_transit.returncode:
        return terrain_transit.returncode
    terrain_zoning = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_terrain_zoning_portable.py')], cwd=ROOT)
    if terrain_zoning.returncode:
        return terrain_zoning.returncode
    terrain_spawn = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_terrain_spawn_portable.py')], cwd=ROOT)
    if terrain_spawn.returncode:
        return terrain_spawn.returncode
    floor_stairs = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_floor_stairs_portable.py')], cwd=ROOT)
    if floor_stairs.returncode:
        return floor_stairs.returncode
    floor_connections = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_floor_connections_portable.py')], cwd=ROOT)
    if floor_connections.returncode:
        return floor_connections.returncode
    floor_elevator = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_floor_elevator_portable.py')], cwd=ROOT)
    if floor_elevator.returncode:
        return floor_elevator.returncode
    floor_entrances = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_floor_entrances_portable.py')], cwd=ROOT)
    if floor_entrances.returncode:
        return floor_entrances.returncode
    floor_editor_walk = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_floor_editor_walk_portable.py')], cwd=ROOT)
    if floor_editor_walk.returncode:
        return floor_editor_walk.returncode
    floor_terrain = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_floor_terrain_portable.py')], cwd=ROOT)
    if floor_terrain.returncode:
        return floor_terrain.returncode
    floor_maximum = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_floor_maximum_portable.py')], cwd=ROOT)
    if floor_maximum.returncode:
        return floor_maximum.returncode
    neighborhood = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_neighborhood_portable.py'),
        *(['--visible-import', '--import-accessibility-dummy'] if os.name == 'nt' else [])], cwd=ROOT)
    if neighborhood.returncode:
        return neighborhood.returncode
    neighborhood_themes = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_neighborhood_portable.py'), '--themes',
        *(['--visible-import', '--import-accessibility-dummy'] if os.name == 'nt' else [])], cwd=ROOT)
    if neighborhood_themes.returncode:
        return neighborhood_themes.returncode
    small_props = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_small_prop_portable.py'),
        *(['--visible-import', '--import-accessibility-dummy'] if os.name == 'nt' else [])], cwd=ROOT)
    if small_props.returncode:
        return small_props.returncode
    ambience = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_ambience_portable.py')], cwd=ROOT)
    if ambience.returncode:
        return ambience.returncode
    place_audio = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_ambience_portable.py'),
        '--place', str(ROOT / 'output' / 'verification' / 'asset_expansion' / 'I18')], cwd=ROOT)
    if place_audio.returncode:
        return place_audio.returncode
    weather = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_weather_portable.py')], cwd=ROOT)
    if weather.returncode:
        return weather.returncode
    props = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_props_portable.py')], cwd=ROOT)
    if props.returncode:
        return props.returncode
    driving = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_driving_portable.py')], cwd=ROOT)
    if driving.returncode:
        return driving.returncode
    photo = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_photo_portable.py')], cwd=ROOT)
    if photo.returncode:
        return photo.returncode
    supplemental = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_supplemental_portable.py')], cwd=ROOT)
    if supplemental.returncode:
        return supplemental.returncode
    rendering = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_rendering_budget_portable.py'), '--prepare'], cwd=ROOT)
    if rendering.returncode:
        return rendering.returncode
    reviewed = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_reviewed_sprites_portable.py')], cwd=ROOT)
    if reviewed.returncode:
        return reviewed.returncode
    names = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_reviewed_names_portable.py')], cwd=ROOT)
    if names.returncode:
        return names.returncode
    themes = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_asset_themes_portable.py')], cwd=ROOT)
    if themes.returncode:
        return themes.returncode
    capabilities = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_asset_capabilities_portable.py')], cwd=ROOT)
    if capabilities.returncode:
        return capabilities.returncode
    scale = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_asset_scale_portable.py')], cwd=ROOT)
    if scale.returncode:
        return scale.returncode
    styles = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_style_suggestions_portable.py')], cwd=ROOT)
    if styles.returncode:
        return styles.returncode
    semantic = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_semantic_search_portable.py')], cwd=ROOT)
    if semantic.returncode:
        return semantic.returncode
    health = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_asset_health_portable.py')], cwd=ROOT)
    if health.returncode:
        return health.returncode
    anchors = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_interaction_anchors_portable.py')], cwd=ROOT)
    if anchors.returncode:
        return anchors.returncode
    kits = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_interior_kits_portable.py')], cwd=ROOT)
    if kits.returncode:
        return kits.returncode
    tasks = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_task_collections_portable.py')], cwd=ROOT)
    if tasks.returncode:
        return tasks.returncode
    kit_layouts = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_interior_kit_portable.py')], cwd=ROOT)
    if kit_layouts.returncode:
        return kit_layouts.returncode
    # Windows 4.7.1 can fault at headless editor shutdown even with its
    # accessibility bridge disabled. Exercise ordinary graphical import there.
    recent_args = ['--visible-import'] if os.name == 'nt' else []
    recent_assets = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_recent_asset_portable.py'), *recent_args], cwd=ROOT)
    if recent_assets.returncode:
        return recent_assets.returncode
    # This slice retains failed stock imports as evidence. Its explicit Windows
    # import-only dummy driver selects a separate documented import setting;
    # the independently launched runtime keeps its normal accessibility driver.
    companion_args = ['--visible-import', '--import-accessibility-dummy'] if os.name == 'nt' else []
    companions = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_companion_portable.py'), *companion_args], cwd=ROOT)
    if companions.returncode:
        return companions.returncode
    collection_args = ['--visible-import', '--import-accessibility-dummy'] if os.name == 'nt' else []
    collections = run_portable([sys.executable, '-u', str(ROOT / 'tools' / 'verify_collection_portable.py'), *collection_args], cwd=ROOT)
    if collections.returncode:
        return collections.returncode
    if not portable_started:
        print(f'Unknown standalone check: {portable_start}', file=sys.stderr)
        return 2
    current_names = {name for name, *_ in checks}
    leaked = []
    for path in logs.glob('*.log'):
        if path.stem not in current_names and not re.fullmatch(
                r'(?:portable_(?:import|runtime|main)_[23]d|\w+_portable_[23]d_(?:import|runtime|main))', path.stem):
            continue
        if 'were leaked at exit' in path.read_text(encoding='utf-8', errors='replace'):
            leaked.append(path.name)
    if leaked:
        print('FAIL: ObjectDB shutdown leaks: ' + ', '.join(sorted(leaked)), file=sys.stderr)
        return 1
    scope = 'Selected' if portable_start or '--from-check' in sys.argv else 'All'
    print(f'{scope} setup checks passed, including shutdown leak audit. Logs: {logs}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
