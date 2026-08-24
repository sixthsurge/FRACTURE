package util;

import dev.irisshaders.aperture.api.commands.CompositeCommand;
import dev.irisshaders.aperture.api.commands.ComputeCommand;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.ObjectShaderBuilder;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramUsage;
import java.util.ArrayList;

/// Helper for reducing boilerplate in program creation.
public class ProgramFactory {
	private record IntExport(String name, int value) {}

	private record FloatExport(String name, float value) {}

	private record BoolExport(String name, boolean value) {}

	private PipelineConfig pipeline;
	private Screen screen;
	private StageList currentStage;
	private ArrayList<IntExport> globalIntExports;
	private ArrayList<FloatExport> globalFloatExports;
	private ArrayList<BoolExport> globalBoolExports;

	public ProgramFactory(PipelineConfig pipeline, Screen screen) {
		this.pipeline = pipeline;
		this.screen = screen;
		currentStage = null;
		globalIntExports = new ArrayList<>();
		globalFloatExports = new ArrayList<>();
		globalBoolExports = new ArrayList<>();
	}

	public void setCurrentStage(StageList stage) { currentStage = stage; }

	public void exportIntGlobally(String name, int value) {
		globalIntExports.add(new IntExport(name, value));
	}

	public void exportFloatGlobally(String name, float value) {
		globalFloatExports.add(new FloatExport(name, value));
	}

	public void exportBoolGlobally(String name, boolean value) {
		globalBoolExports.add(new BoolExport(name, value));
	}

	public ComputeCommand compute(String name, String path, String entryPoint) {
		ComputeCommand command = currentStage.compute(name, path, entryPoint);

		for (IntExport intExport : globalIntExports) {
			command = command.exportInt(intExport.name(), intExport.value());
		}
		for (FloatExport floatExport : globalFloatExports) {
			command
				= command.exportFloat(floatExport.name(), floatExport.value());
		}
		for (BoolExport boolExport : globalBoolExports) {
			command = command.exportBool(boolExport.name(), boolExport.value());
		}

		return command;
	}

	public ComputeCommand compute2d(
		String name,
		String path,
		String entryPoint,
		int totalWidth,
		int totalHeight,
		int workgroupWidth,
		int workgroupHeight
	) {
		int dispatchWidth = Math.ceilDiv(totalWidth, workgroupWidth);
		int dispatchHeight = Math.ceilDiv(totalHeight, workgroupHeight);

		return compute(name, path, entryPoint)
			.dispatch2D(dispatchWidth, dispatchHeight)
			.exportInt("DISPATCH_SIZE_X", dispatchWidth)
			.exportInt("DISPATCH_SIZE_Y", dispatchHeight)
			.exportInt("DISPATCH_SIZE_Z", 1);
	}

	public ComputeCommand compute3d(
		String name,
		String path,
		String entryPoint,
		int totalWidth,
		int totalHeight,
		int totalDepth,
		int workgroupWidth,
		int workgroupHeight,
		int workgroupDepth
	) {
		int dispatchWidth = Math.ceilDiv(totalWidth, workgroupWidth);
		int dispatchHeight = Math.ceilDiv(totalHeight, workgroupHeight);
		int dispatchDepth = Math.ceilDiv(totalDepth, workgroupDepth);

		return compute(name, path, entryPoint)
			.dispatch3D(dispatchWidth, dispatchHeight, dispatchDepth)
			.exportInt("DISPATCH_SIZE_X", dispatchWidth)
			.exportInt("DISPATCH_SIZE_Y", dispatchHeight)
			.exportInt("DISPATCH_SIZE_Z", dispatchDepth);
	}

	public ComputeCommand renderSizedCompute(
		String name,
		String path,
		String entryPoint,
		int workgroupWidth,
		int workgroupHeight
	) {
		return compute2d(
			name,
			path,
			entryPoint,
			screen.renderWidth(),
			screen.renderHeight(),
			workgroupWidth,
			workgroupHeight
		);
	}

	public ComputeCommand windowSizedCompute(
		String name,
		String path,
		String entryPoint,
		int workgroupWidth,
		int workgroupHeight
	) {
		return compute2d(
			name,
			path,
			entryPoint,
			screen.windowWidth(),
			screen.windowHeight(),
			workgroupWidth,
			workgroupHeight
		);
	}

	public CompositeCommand
	composite(String name, String path, String entryPoint) {
		CompositeCommand command
			= currentStage.composite(name, path, entryPoint);

		for (IntExport intExport : globalIntExports) {
			command = command.exportInt(intExport.name(), intExport.value());
		}
		for (FloatExport floatExport : globalFloatExports) {
			command
				= command.exportFloat(floatExport.name(), floatExport.value());
		}
		for (BoolExport boolExport : globalBoolExports) {
			command = command.exportBool(boolExport.name(), boolExport.value());
		}

		return command;
	}

	public ObjectShaderBuilder
	object(ProgramUsage usage, String path, String module) {
		ObjectShaderBuilder builder = pipeline.object(usage, path, module);

		for (IntExport intExport : globalIntExports) {
			builder = builder.exportInt(intExport.name(), intExport.value());
		}
		for (FloatExport floatExport : globalFloatExports) {
			builder
				= builder.exportFloat(floatExport.name(), floatExport.value());
		}
		for (BoolExport boolExport : globalBoolExports) {
			builder = builder.exportBool(boolExport.name(), boolExport.value());
		}

		return builder;
	}
}
