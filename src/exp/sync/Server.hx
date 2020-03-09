package exp.sync;

#if !macro
import exp.sync.transport.Server as Transport;
import tink.streams.Stream;
import tink.Chunk;

using tink.io.Source;

class Server<T> {
	public static macro function create(binder, serializer, model);
	
	static function _create<T>(binder:exp.sync.transport.Server.Binder, observer:(signal:SignalTrigger<Yield<Chunk, Error>>)->Void):Promise<Server<T>> {
		final handler = incoming -> {
			final signal = Signal.trigger();
			final outgoing:RealSource = new SignalStream(signal);
			observer(signal);
			outgoing;
		}
		return binder(handler).next(Server.new);
	}
	
	final transport:Transport;
	
	function new(transport) {
		this.transport = transport;
	}
}


#else


import exp.sync.macro.Macro;
import haxe.macro.Expr;
import haxe.macro.Context;
using tink.MacroApi;

class Server {
	public static macro function create(binder, serializer, model) {
		var type = Context.typeof(model);
		var fields = Macro.getFields(type, model.pos);
		var full = EObjectDecl([for(field in fields) {field: field.name, expr: macro $p{['model', field.name, 'value']}}]).at();
		var partials = [for(field in fields) macro $p{['model', field.name]}.bind(null, v -> send(Partial($i{field.name.toCamelCase()}(v))))];
		var modelCt = type.toComplex();
		var diffCt = macro:exp.sync.Diff<$modelCt>;
		
		var observer = macro function(signal) {
			
			function send(v:$diffCt) {
				var chunk = serializer.serialize(v) + '|';
				signal.trigger(Data(chunk));
			}
			
			send(Full($full));
			$b{partials};
		}
		
		return macro {
			@:pos(serializer.pos) var serializer:why.Serializer<$diffCt, tink.Chunk> = $serializer;
			@:pos(model.pos) var model = $model;
			@:privateAccess exp.sync.Server._create($binder, $observer);
		}
	}
}
#end