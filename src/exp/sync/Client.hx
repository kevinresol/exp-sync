package exp.sync;

#if !macro
import exp.sync.transport.Client as Transport;
import tink.io.StreamParser;
import tink.streams.Stream;
import tink.state.*;
import tink.Chunk;

using tink.io.Source;

@:genericBuild(exp.sync.Client.build())
class Client<T> {}

@:genericBuild(exp.sync.Client.buildStates())
class States<T> {}

class ClientBase<T> {
	// TODO: implement proper stream parser without needing to split with delimiter
	static final DELIMITER:Chunk = '|';
	
	public final model:Future<T>;
	
	final first = Future.trigger();
	
	public function new(transport:Transport, serializer) {
		final signal = Signal.trigger();
		final outgoing:RealSource = new SignalStream(signal);
		var incoming = transport.connect(outgoing);
		model = first;
		parse(incoming);
	}
	
	function parse(incoming:RealSource):Void throw 'abstract';
}
#else

import exp.sync.macro.Macro;
import haxe.macro.Expr;
import tink.macro.BuildCache;
using tink.MacroApi;

class Client {
	
	public static function build() {
		return BuildCache.getType('exp.sync.Client', (ctx:BuildContext) -> {
			var name = ctx.name;
			var type = ctx.type;
			var modelCt = ctx.type.toComplex();
			var diffCt = macro:exp.sync.Diff<$modelCt>;
			
			var fields = Macro.getFields(ctx.type, ctx.pos);
			var init = [for(field in fields) {
				var name = field.name;
				macro states.$name = new tink.state.State(v.$name);
			}];
			var obj = EObjectDecl([for(field in fields) {
				var name = field.name;
				{
					field: name,
					expr: macro states.$name,
				}
			}]).at();
			init.push(macro first.trigger($obj));
			
			var parts:Array<Case> = [for(field in fields) {
				var name = field.name;
				{
					values: [macro Partial($i{name.toPascalCase()}(v))],
					expr: macro states.$name.set(v),
				}
			}];
			
			var switchExpr = ESwitch(
				macro data, 
				[{values: [macro Full(v)], expr: macro $b{init}}].concat(parts),
				null
			).at();
			
			var def = macro class $name extends exp.sync.Client.ClientBase<$modelCt> {
				var states = new exp.sync.Client.States<$modelCt>();
				
				override function parse(incoming:tink.io.Source.RealSource) {
					var parser = new tink.io.StreamParser.Splitter(exp.sync.Client.ClientBase.DELIMITER);
					tink.io.Source.RealSourceTools.parseStream(incoming, parser)
						.map(o -> switch o {
							case haxe.ds.Option.Some(chunk): 
								var v = tink.Json.parse(((chunk:tink.Chunk):$diffCt));
								// trace(v);
								v;
							case haxe.ds.Option.None: 
								tink.core.Outcome.Failure(new tink.core.Error('unexpected end'));
						})
						.forEach(data -> {
							apply(data);
							tink.streams.Stream.Handled.Resume;
						})
						.handle(function(o) switch o {
							case Depleted: trace('depleted');
							case Failed(e): trace(e);
							case Halted(_): trace('halted');
						});
				}
	
				function apply(data:$diffCt) {
					$switchExpr;
				}
			}
			
			def.pack = ['exp', 'sync'];
			return def;
		});
	}
		
	public static function buildStates() {
		return BuildCache.getType('exp.sync.States', (ctx:BuildContext) -> {
			var name = ctx.name;
			var type = ctx.type;
		
			var def = macro class $name {
				public function new() {}
			}
			for(field in Macro.getFields(ctx.type, ctx.pos)) {
				var ct = field.type.toComplex();
				def.fields.push({
					access: [APublic],
					name: field.name,
					kind: FVar(macro:tink.state.State<$ct>, null),
					pos: field.pos,
				});
			}
			
			def.pack = ['exp', 'sync'];
			return def;
		});
	}
}

#end