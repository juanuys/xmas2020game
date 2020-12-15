import hxd.Key in K;
import Std;
import haxe.io.Bytes;

class EnvPart extends h2d.SpriteBatch.BatchElement {

	public var speed : Float;
	public var rspeed : Float;

	public function new(t) {
		super(t);
		x = Math.random() * Game.LW * 32;
		y = Math.random() * Game.LH * 32;
		speed = 1.5 + Math.random() * 3;
		rspeed = 0.02 * (1 + Math.random());
	}

}

class GIFFrame {
	public var key: String;
	public var pixels: Bytes;

	public function new(key, pixels) {
		this.key = key;
		this.pixels = pixels;
	}
}

class SinusDeform extends hxsl.Shader {

	static var SRC = {

		@global var time : Float;
		@param var speed : Float;
		@param var frequency : Float;
		@param var amplitude : Float;

		var calculatedUV : Vec2;
		var absolutePosition : Vec4;

		function fragment() {
			calculatedUV.x += sin(absolutePosition.y * frequency + time * speed + absolutePosition.x * 0.1) * amplitude;
		}

	};

	public function new( frequency = 10., amplitude = 0.01, speed = 1. ) {
		super();
		this.frequency = frequency;
		this.amplitude = amplitude;
		this.speed = speed;
	}

}

@:publicFields
class Game extends hxd.App {

	static var LW = 13;
	static var LH = 13;

	static var LAYER_SOIL = 0;
	static var LAYER_ENT_UNDER = 1;
	static var LAYER_COL = 2;
	static var LAYER_ENT = 3;
	static var LAYER_CARRY = 4;
	static var LAYER_HERO = 5;
	static var LAYER_PARTS = 6;
	static var LAYER_ENVP = 7;


	var currentLevel : Int;

	var tiles : h2d.Tile;
	var level : Data.Level;
	var soils : Array<Data.Soil>;
	var entities : Array<ent.Entity> = [];
	var world : h2d.Layers;
	var collides : Array<Int> = [];
	var dbgCol : h2d.TileGroup;
	var hero : ent.Hero;
	var soilLayer : h2d.TileGroup;
	var pad : hxd.Pad;
	var allActive : Bool;

	var bg : h2d.Object;
	var clouds = [];

	var parts : h2d.SpriteBatch;
	var way : Float = 1.;
	var bmpTrans : h2d.Bitmap;

	var hueShader = new h3d.shader.ColorMatrix();
	var hueShaderHalf = new h3d.shader.ColorMatrix();

	var hueValue = 0;
	var currentHue = 0.;

	var winds : Array<hxd.res.Sound> = [];
	var windTimer = 0.;

	var hauntSounds : Array<hxd.res.Sound> = [];
	var hauntSoundsTimer = 10.0;

	var jingleBellSound: hxd.res.Sound;
	var playJingleBells: Bool = true;

	var title : h2d.Bitmap;

	var frameCounter = 0;
	var recordGIF = false;
	var gifFrames: Array<GIFFrame> = [];

	static var save = hxd.Save.load({ volume : 1., level : #if release 0 #else 9 #end });

	override function init() {

		s2d.setFixedSize(LW * 32, LH * 32);
		currentLevel = save.level;

		var i = 1;
		while( true )
			try winds.push(hxd.Res.load("sfx/wind" + (i++) + ".wav").toSound()) catch( e : hxd.res.NotFound ) break;

		i = 1;
		while( true )
			try hauntSounds.push(hxd.Res.load("sfx/haunt" + (i++) + ".wav").toSound()) catch( e : hxd.res.NotFound ) break;

		jingleBellSound = hxd.Res.load("sfx/jinglebells.wav").toSound();

		// preload sounds
		for( s in hxd.Res.load("sfx") )
			s.toSound().getData();

		world = new h2d.Layers(s2d);
		world.filter = new h2d.filter.Bloom(0.5,0.2,3);
		tiles = hxd.Res.tiles.toTile();
		soilLayer = new h2d.TileGroup(tiles);

		bg = new h2d.Object(world);
		bg.filter = new h2d.filter.Blur(3);
		bg.filter.smooth = true;
		var tbg = tiles.sub(32 * 3, 64, 32, 32);
		tbg.scaleToSize(LW * 32, LH * 32);
		new h2d.Bitmap(tbg, bg).addShader(hueShaderHalf);

		var rnd = new hxd.Rand(42);
		var ctiles = [for( i in 0...3 ) tiles.sub(i * 32 * 3, 192, 32 * 3, 64, -32 * 3 >> 1, -32)];
		trace(ctiles);
		for( i in 0...100 ) {
			var b = new h2d.Bitmap(ctiles[rnd.random(ctiles.length)], bg);
			b.smooth = true;
			b.addShader(hueShaderHalf);
			clouds.push({
				sc: 0.7 + rnd.rand(),
				x: rnd.rand() * (LW * 32 + 200) - 100,
				y: rnd.rand() * (LH * 32 + 200) - 100,
				speed: rnd.rand() + 1,
				spr: b,
				t: Math.random() * Math.PI * 2
			});
		}

		var ptiles = hxd.Res.envParts.toTile().split();
		parts = new h2d.SpriteBatch(ptiles[0]);
		world.add(parts, LAYER_ENVP);
		for( i in 0...100 )
			parts.add(new EnvPart(ptiles[Std.random(ptiles.length)]));

		world.add(soilLayer, LAYER_SOIL);

		pad = hxd.Pad.createDummy();
		hxd.Pad.wait(function(p) pad = p);

		hxd.Res.data.watch(onReload);

		#if !release
		initLevel();
		#else

		// TODO swap out the title here with intermediary screens
		title = new h2d.Bitmap(hxd.Res.title.toTile(), world);
		title.scale(2);

		var tf = new h2d.Text(hxd.res.DefaultFont.get(), title);
		tf.scale(0.5);
		tf.textColor = 0;
		tf.text = "Space / A to start";
		if( save.level > 0 )
			tf.text += "\nEsc to reset save";
		tf.x = ((Std.int(LW) * 32) - (Std.int(tf.textWidth) * 2)) >> 1;
		tf.y = 180;

		#end

	}

	function onReload() {
		Data.load(hxd.Res.data.entry.getText());
		initLevel(true);
	}

	function nextLevel() {
		haxe.Timer.delay(function() {


			if( currentLevel == 0 )
				hxd.Res.sfx.ok.play();
			else
				hxd.Res.sfx.noteEnd.play();

			for( e in entities.copy() )
				if( e.hasFlag(NeedActive) )
					e.remove();
			bg.visible = false;
			parts.visible = false;
			if( hero != null ) hero.remove();

			var t = new h3d.mat.Texture(LW * 32, LH * 32, [Target]);
			var old = world.filter;
			world.filter = null;
			world.drawTo(t);
			world.filter = old;
			bmpTrans = new h2d.Bitmap(h2d.Tile.fromTexture(t));

			bg.visible = true;
			parts.visible = true;

			currentLevel++;
			initLevel();

			world.add(bmpTrans, LAYER_ENT - 1);

		},0);
	}

	function initLevel( ?reload ) {


		hueValue = 0;

		level = Data.level.all[currentLevel];
		if( level == null )
			return;

		if( save.level != currentLevel ) {
			save.level = currentLevel;
			hxd.Save.save(save);
		}

		if( !reload )
			for( e in entities.copy() )
				e.remove();

		soils = level.soils.decode(Data.soil.all);

		while( soilLayer.numChildren > 0 )
			soilLayer.getChildAt(0).remove();

		var cdb = new h2d.CdbLevel(Data.level, currentLevel);
		cdb.redraw();
		var layer = cdb.getLevelLayer("border");
		if( layer != null ) {
			layer.content.addShader(new SinusDeform(0.1,0.002,3));
			soilLayer.addChild(layer.content);
		}
		var layer = cdb.getLevelLayer("border2");
		if( layer != null ) {
			layer.content.addShader(new SinusDeform(0.1,0.002,3));
			soilLayer.addChild(layer.content);
		}

		var objects = level.objects.decode(Data.object.all);
		var empty = tiles.sub(0, 2 * 32, 32, 32);
		soilLayer.clear();
		for( y in 0...LH )
			for( x in 0...LW ) {
				var s = soils[x + y * LW];
				if( s.id != Block2 ) {
					if( s.id != Block )
						soilLayer.add(x * 32, y * 32, empty);
					if( s.id != Empty )
						soilLayer.add(x * 32, y * 32, tiles.sub(s.image.x * 32, s.image.y * 32, 32, 32));
				}
				if( !reload )
					createObject(objects[x + y * LW].id, x, y);
			}
		updateCol();
		collides = [];
		@:privateAccess hero.rebuildCol();
	}

	function createObject(kind : Data.ObjectKind, x, y) : ent.Entity {
		switch( kind ) {
		case None:
			return null;
		case Hero:
			return hero = new ent.Hero(x, y);
		default:
		}
		return new ent.Object(kind, x, y);
	}

	function getSoil( x, y ) : Data.SoilKind {
		if( x < 0 || y < 0 || x >= LW || y >= LH )
			return Block;
		return soils[x + y * LH].id;
	}

	function pick( x : Float, y : Float ) {
		var ix = Std.int(x);
		var iy = Std.int(y);
		for( e in entities )
			if( Std.int(e.x) == ix && Std.int(e.y) == iy && e.canPick() )
				return e;
		return null;
	}

	function isCollide( e : ent.Entity, x, y ) {
		switch( getSoil(x, y) ) {
		case Block:
			return true;
		case Block2 if( e != hero || !hero.doCarry(Wings,true) ):
			return true;
		default:
		}
		var i = collides[x + y * LW];
		if( i > 0 ) {

			if( e == hero && i < 16 ) {
				// skip
			} else {
				return true;
			}
		}

		for( e2 in entities )
			if( e2 != e && Std.int(e2.x) == x && Std.int(e2.y) == y && e2.isCollide(e) )
				return true;

		return false;
	}

	function updateCol() {
		return;
		var t = h2d.Tile.fromColor(0xFF0000, 32, 32);
		if( dbgCol == null ) {
			dbgCol = new h2d.TileGroup(t);
			dbgCol.alpha = 0.2;
			world.add(dbgCol, LAYER_COL);
		}
		dbgCol.clear();
		for( y in 0...LH )
			for( x in 0...LW )
				if( isCollide(null, x, y) )
					dbgCol.add(x * 32, y * 32, t);
	}


	override function update( dt : Float ) {
		dt *= 60; // old dt support

		if( bmpTrans != null ) {
			bmpTrans.alpha -= 0.05 * dt;
			if( bmpTrans.alpha < 0 ) {
				bmpTrans.tile.getTexture().dispose();
				bmpTrans.remove();
				bmpTrans = null;
			}
		}

		#if !release

		if( K.isPressed("H".code) )
			hueValue = 1 - hueValue;

		if( K.isPressed("R".code) || K.isPressed("K".code) ) {
			onReload();
			initLevel();
		}

		if( (K.isPressed(K.BACKSPACE) || K.isPressed(K.PGUP)) && currentLevel > 0 ) {
			currentLevel--;
			initLevel();
		}

		if( K.isPressed(K.PGDOWN) && currentLevel < Data.level.all.length - 1 ) {
			currentLevel++;
			initLevel();
		}

		if( K.isPressed("X".code)) {
			if (recordGIF) {
				recordGIF = false;
				for (frame in gifFrames) {
					var filename = "/home/opyate/Pictures/foo/test" + frame.key + ".png";
					sys.io.File.saveBytes(filename, frame.pixels);
				}
			} else {
				recordGIF = true;
				trace("Recording GIF frames. Stop stop/save, press X...");
			}
		}

		#end

		if( K.isPressed("M".code) || K.isPressed("S".code) || K.isPressed(K.F1) ) {
			var mg = hxd.snd.Manager.get().masterChannelGroup;
			mg.volume = 1 - mg.volume;
			save.volume = mg.volume;
			hxd.Save.save(save);
		}


		for( e in entities.copy() )
			e.update(dt);

		allActive = true;
		for( e in entities ) {
			var o = Std.instance(e, ent.Object);
			if( o != null && !o.active && o.hasFlag(NeedActive) )
				allActive = false;
		}

		var ang = Math.PI / 2 + 0.3;
		var cloudAngle = 0.3;


		var curWay = hero != null && hero.movingAmount < 0 ? hero.movingAmount * 20 : 1;
		way = hxd.Math.lerp(way, curWay, 1 - Math.pow(0.5, dt));


		for( c in clouds ) {
			var ds = c.speed * dt * 0.3 * way;

			c.t += ds * 0.01;
			c.spr.setScale(1 + Math.sin(c.t) * 0.2);
			c.spr.scaleX *= c.sc;

			c.x += Math.cos(cloudAngle) * ds;
			c.y += Math.sin(cloudAngle) * ds;
			c.spr.x = c.x;
			c.spr.y = c.y;
			if( c.x > LW * 32 + 100 )
				c.x -= LW * 32 + 300;
			if( c.y > LH * 32 + 100 )
				c.y -= LH * 32 + 300;
			if( c.x < -100 )
				c.x += LW * 32 + 300;
			if( c.y < -100 )
				c.y += LH * 32 + 300;

		}

		parts.hasRotationScale = true;
		for( p in parts.getElements() ) {
			var p = cast(p, EnvPart);
			var ds = dt * p.speed * way;
			p.x += Math.cos(ang) * ds;
			p.y += Math.sin(ang) * ds;
			p.rotation += ds * p.rspeed;
			if( p.x > LW * 32 )
				p.x -= LW * 32;
			if( p.y > LH * 32 )
				p.y -= LH * 32;
			if( p.y < 0 )
				p.y += LH * 32;
			if( p.x < 0 )
				p.x += LW * 32;
		}


		currentHue = hxd.Math.lerp(currentHue, hueValue, 1 - Math.pow(0.95, dt));

		hueShader.matrix.identity();
		hueShaderHalf.matrix.identity();
		hueShader.matrix.colorHue(-Math.PI * currentHue);
		hueShaderHalf.matrix.colorHue(-Math.PI/2 * currentHue);


		windTimer += dt / 60;
		if( windTimer > 0 ) {
			winds[Std.random(winds.length)].play(false, 0.5 + Math.random() * 0.5);
			windTimer -= 0.5 + Math.random() * 0.3;
		}

		if( hauntSoundsTimer > 0 ) {
			var hstRnd = Math.random();
			if (hstRnd < 0.3) {
				hauntSoundsTimer -= hstRnd * 0.1;
			}

			if (playJingleBells && hauntSoundsTimer < 5.0) {
				playJingleBells = false;
				if (Math.random() < 0.25) {
					jingleBellSound.play(false, 0.1 + Math.random() * 0.2);
					// trace("play jingle bells");
				}
			}
			
		} else {
			// play and reset
			// trace("play haunt");
			if (Math.random() < 0.25) {
				hauntSounds[Std.random(hauntSounds.length)].play(false, 0.1 + Math.random() * 0.2);
			}
			hauntSoundsTimer = 10.0;
			playJingleBells = true;
		}

		if( title != null && title.alpha < 1 )  {
			title.alpha -= 0.01 * dt;
			if( title.alpha < 0 ) {
				title.remove();
				title = null;
			}
		}


		if( title != null && title.alpha == 1 ) {
			if( K.isPressed(K.ESCAPE) )
				currentLevel = 0;
			if( K.isPressed(K.ESCAPE) || K.isPressed(K.SPACE) || pad.isPressed(hxd.Pad.DEFAULT_CONFIG.A) || pad.isPressed(hxd.Pad.DEFAULT_CONFIG.B) ) {
				currentLevel--;
				title.alpha = 0.99;
				nextLevel();
			}
		}

		// capture PNG frames for GIF
		if (recordGIF ) { // && frameCounter < 200
			var renderTarget = new h3d.mat.Texture( engine.width, engine.height, [ Target ] );

			engine.pushTarget(renderTarget);
			engine.clear(0, 1);
			s2d.render(engine);
			var pixels = renderTarget.capturePixels();
			
			var frameStr = "00" + frameCounter;
			// 3 digit number, padded with zeros from the left
			frameStr = frameStr.substr(frameStr.length - 3, 3);

			var frame = new GIFFrame(frameStr, pixels.toPNG());
			gifFrames.push(frame);

			// var filename = "/home/opyate/Pictures/foo/test" + frameStr + ".png";
			// sys.io.File.saveBytes(filename, pixels.toPNG());

			engine.popTarget();
		}
		frameCounter++;
	}


	public static var inst : Game;

	static function main() {
		#if js
		hxd.Res.initEmbed();
		#else
		hxd.res.Resource.LIVE_UPDATE = true;
		hxd.Res.initLocal();
		#end
		Data.load(hxd.Res.data.entry.getText());
		hxd.snd.Manager.get().masterChannelGroup.volume = save.volume;
		inst = new Game();
	}

}