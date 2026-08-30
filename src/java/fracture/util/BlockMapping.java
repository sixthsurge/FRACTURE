package fracture.util;

import dev.irisshaders.aperture.api.objects.IBlockState;
import java.util.ArrayList;
import java.util.HashMap;

public class BlockMapping {
	// Fracture block IDs consist of two 8-bit fields:
	// Bit 0-7   | Material ID. This is what's stored in the gbuffer
	//           | and used for shading.
	// Bits 8-15 | Light source ID. This is what's used for LPV
	//           | lighting (also does tinting blocks).
	//
	// IDs are configured by assigning IDs and tags to a name corresponding
	// to a constant exported to the shaders. IDs have priority over tags.

	// Builder object for material ID groups.
	public class MaterialId {
		private BlockMapping mappings;
		private int id;

		private MaterialId(BlockMapping mappings, int id) {
			this.mappings = mappings;
			this.id = id;
		}

		public MaterialId id(String blockId) {
			mappings.materialIdMapping.put(blockId, id);
			return this;
		}

		public MaterialId tag(String tagId) {
			mappings.materialTagMapping.put(tagId, id);
			return this;
		}
	}

	private ArrayList<String> materialGroupNames = new ArrayList<>();
	private HashMap<String, Integer> materialIdMapping = new HashMap<>();
	private HashMap<String, Integer> materialTagMapping = new HashMap<>();

	private HashMap<String, Integer> lightSourceIdMapping = new HashMap<>();
	private HashMap<String, Integer> lightSourceTagMapping = new HashMap<>();

	public BlockMapping() { materialGroupNames.add("MAT_DEFAULT"); }

	public void addGlobalExports(PipelineBuilder builder) {
		// Export constants for block IDs.
		for (int i = 0; i < materialGroupNames.size(); ++i) {
			builder.exportIntGlobally(materialGroupNames.get(i), i);
		}
	}

	public MaterialId material(String shaderConstantName) {
		int id = materialGroupNames.size();
		materialGroupNames.add(shaderConstantName);
		return new MaterialId(this, id);
	}

	public int getBlockId(IBlockState block) {
		return getId(block, materialIdMapping, materialTagMapping)
			+ (getId(block, lightSourceIdMapping, lightSourceTagMapping) << 8);
	}

	private int getId(
		IBlockState block,
		HashMap<String, Integer> idMapping,
		HashMap<String, Integer> tagMapping
	) {
		final var id = block.getBlockId();
		final var fromId = idMapping.get(id.toString());
		if (fromId != null) {
			return fromId.intValue();
		}

		for (var tag : block.getTagList()) {
			final var fromTag = tagMapping.get(tag.toString());
			if (fromTag != null) {
				return fromTag.intValue();
			}
		}

		return 0;
	}
}
